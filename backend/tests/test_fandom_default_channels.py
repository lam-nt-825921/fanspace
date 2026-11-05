"""Integration tests for default channel seeding and DefaultMembershipPermissionAdapter."""

import uuid
from datetime import datetime, timedelta, timezone
import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import delete

from app.core.database import AsyncSessionLocal
from app.core.permissions import Permission
from app.core.security import create_access_token, get_password_hash
from app.main import app
from app.modules.chat.models import Channel
from app.modules.fandom.models import Fandom, FandomMember
from app.modules.identity.models import User
from app.modules.rbac.models import MemberRole, Role


async def _cleanup_fandom_channel_entities(
    user_ids: list[uuid.UUID],
    fandom_ids: list[uuid.UUID],
) -> None:
    """Cleans up test users, fandoms, members, roles, and channels."""
    async with AsyncSessionLocal() as db:
        if fandom_ids:
            await db.execute(delete(Channel).where(Channel.fandom_id.in_(fandom_ids)))
            await db.execute(delete(MemberRole).where(MemberRole.fandom_id.in_(fandom_ids)))
            await db.execute(delete(Role).where(Role.fandom_id.in_(fandom_ids)))
            await db.execute(delete(FandomMember).where(FandomMember.fandom_id.in_(fandom_ids)))
            await db.execute(delete(Fandom).where(Fandom.id.in_(fandom_ids)))
        if user_ids:
            await db.execute(delete(User).where(User.id.in_(user_ids)))
        await db.commit()


@pytest.mark.asyncio
async def test_default_channels_seeded_on_fandom_creation_and_member_permissions():
    """Verifies 3 default channels are created and per-channel permissions match member roles."""
    suffix = uuid.uuid4().hex[:8]
    owner = User(
        username=f"f_owner_{suffix}",
        email=f"f_owner_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("Password123!"),
        display_name="Creator Owner",
        is_active=True,
    )
    member = User(
        username=f"f_member_{suffix}",
        email=f"f_member_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("Password123!"),
        display_name="Active Fan",
        is_active=True,
    )
    outsider = User(
        username=f"f_outsider_{suffix}",
        email=f"f_outsider_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("Password123!"),
        display_name="Outsider Guest",
        is_active=True,
    )

    async with AsyncSessionLocal() as db:
        db.add_all([owner, member, outsider])
        await db.commit()
        owner_id = owner.id
        member_id = member.id
        outsider_id = outsider.id

    fandom_id: uuid.UUID | None = None
    try:
        owner_token = create_access_token(data={"sub": str(owner_id)})
        member_token = create_access_token(data={"sub": str(member_id)})
        outsider_token = create_access_token(data={"sub": str(outsider_id)})
        slug = f"idol-space-{suffix}"

        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            create_fandom_res = await ac.post(
                "/api/v1/fandoms",
                headers={"Authorization": f"Bearer {owner_token}"},
                json={
                    "name": f"Idol Space {suffix}",
                    "slug": slug,
                    "description": "Cộng đồng fan chính thức",
                    "category": "Thần tượng (Idol)",
                    "admission_mode": "OPEN",
                    "rules_tos": "1. Tôn trọng lẫn nhau\n2. Không spam",
                },
            )
            assert create_fandom_res.status_code == 201, create_fandom_res.text
            fandom_id = uuid.UUID(create_fandom_res.json()["fandom_id"])

            # Outsider is blocked from accessing internal fandom channels.
            outsider_res = await ac.get(
                f"/api/v1/fandoms/{slug}/channels",
                headers={"Authorization": f"Bearer {outsider_token}"},
            )
            assert outsider_res.status_code == 403

            # Member joins the fandom and fetches channels.
            join_res = await ac.post(
                f"/api/v1/fandoms/{slug}/join",
                headers={"Authorization": f"Bearer {member_token}"},
            )
            assert join_res.status_code == 200

            member_ch_res = await ac.get(
                f"/api/v1/fandoms/{slug}/channels",
                headers={"Authorization": f"Bearer {member_token}"},
            )
            assert member_ch_res.status_code == 200, member_ch_res.text
            channels = member_ch_res.json()["channels"]
            assert len(channels) == 3

            ann_ch = next(c for c in channels if c["is_announcement"] is True)
            text_ch = next(c for c in channels if c["type"] == "TEXT" and not c["is_announcement"])
            voice_ch = next(c for c in channels if c["type"] == "VOICE")

            assert Permission.READ_MESSAGES.value in ann_ch["my_permissions"]
            assert Permission.SEND_MESSAGES.value not in ann_ch["my_permissions"]
            assert Permission.SEND_ANNOUNCEMENT.value not in ann_ch["my_permissions"]

            assert Permission.READ_MESSAGES.value in text_ch["my_permissions"]
            assert Permission.SEND_MESSAGES.value in text_ch["my_permissions"]
            assert Permission.MANAGE_CHANNELS.value not in text_ch["my_permissions"]

            assert Permission.VOICE_CONNECT.value in voice_ch["my_permissions"]
            assert Permission.VOICE_SPEAK.value in voice_ch["my_permissions"]

            # Owner has MANAGE_CHANNELS and SEND_ANNOUNCEMENT.
            owner_ch_res = await ac.get(
                f"/api/v1/fandoms/{slug}/channels",
                headers={"Authorization": f"Bearer {owner_token}"},
            )
            assert owner_ch_res.status_code == 200
            owner_channels = owner_ch_res.json()["channels"]
            owner_ann = next(c for c in owner_channels if c["is_announcement"] is True)
            assert Permission.SEND_ANNOUNCEMENT.value in owner_ann["my_permissions"]
            assert Permission.SEND_MESSAGES.value in owner_ann["my_permissions"]
            assert Permission.MANAGE_CHANNELS.value in owner_ch_res.json()["my_fandom_permissions"]
    finally:
        await _cleanup_fandom_channel_entities(
            [owner_id, member_id, outsider_id],
            [fandom_id] if fandom_id else [],
        )


@pytest.mark.asyncio
async def test_muted_member_restrictions_and_last_channel_delete_guard():
    """Verifies muted members cannot send messages and the last channel cannot be deleted."""
    suffix = uuid.uuid4().hex[:8]
    owner = User(
        username=f"m_owner_{suffix}",
        email=f"m_owner_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("Password123!"),
        display_name="Owner",
        is_active=True,
    )
    muted_user = User(
        username=f"m_muted_{suffix}",
        email=f"m_muted_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("Password123!"),
        display_name="Muted User",
        is_active=True,
    )

    async with AsyncSessionLocal() as db:
        db.add_all([owner, muted_user])
        await db.flush()

        fandom = Fandom(
            name=f"Mute Fandom {suffix}",
            slug=f"mute-fandom-{suffix}",
            description="Test muted permissions",
            category="Âm nhạc",
            admission_mode="OPEN",
            is_public=True,
            member_count=2,
            owner_id=owner.id,
        )
        db.add(fandom)
        await db.flush()

        db.add(FandomMember(fandom_id=fandom.id, user_id=owner.id, status="ACTIVE"))
        db.add(
            FandomMember(
                fandom_id=fandom.id,
                user_id=muted_user.id,
                status="MUTED",
                muted_until=datetime.now(timezone.utc) + timedelta(hours=2),
            )
        )
        await db.commit()

        owner_id = owner.id
        muted_id = muted_user.id
        fandom_id = fandom.id
        slug = fandom.slug

    try:
        owner_token = create_access_token(data={"sub": str(owner_id)})
        muted_token = create_access_token(data={"sub": str(muted_id)})

        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            muted_res = await ac.get(
                f"/api/v1/fandoms/{slug}/channels",
                headers={"Authorization": f"Bearer {muted_token}"},
            )
            assert muted_res.status_code == 200
            muted_channels = muted_res.json()["channels"]
            text_ch = next(c for c in muted_channels if c["type"] == "TEXT" and not c["is_announcement"])
            assert Permission.READ_MESSAGES.value in text_ch["my_permissions"]
            assert Permission.SEND_MESSAGES.value not in text_ch["my_permissions"]

            ch_ids = [c["id"] for c in muted_channels]
            for cid in ch_ids[:-1]:
                del_res = await ac.delete(
                    f"/api/v1/fandoms/{slug}/channels/{cid}",
                    headers={"Authorization": f"Bearer {owner_token}"},
                )
                assert del_res.status_code == 200

            last_del_res = await ac.delete(
                f"/api/v1/fandoms/{slug}/channels/{ch_ids[-1]}",
                headers={"Authorization": f"Bearer {owner_token}"},
            )
            assert last_del_res.status_code == 400
            assert "kênh duy nhất" in last_del_res.json()["detail"]
    finally:
        await _cleanup_fandom_channel_entities([owner_id, muted_id], [fandom_id])
