"""Integration tests for Fandom Profile & Appearance Management (FR-07).

Covers:
1. Owner updates fandom profile metadata (name, description, category, rules_tos, admission_mode).
2. Owner updates branding media (avatar_url, banner_url, illustration_urls).
3. Non-owner attempting to update profile is rejected with 403 Forbidden.
4. Validation constraints on illustration_urls (max 5 items, max 1 video).
"""

import uuid
import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import delete

from app.core.database import AsyncSessionLocal
from app.core.security import create_access_token, get_password_hash
from app.main import app
from app.modules.chat.models import Channel
from app.modules.fandom.models import Fandom, FandomMember
from app.modules.identity.models import User
from app.modules.rbac.models import MemberRole, Role


async def _cleanup(user_ids: list[uuid.UUID], fandom_ids: list[uuid.UUID]) -> None:
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
async def test_owner_updates_fandom_profile_successfully():
    """Verifies that the owner can update name, description, category, admission mode, rules and media."""
    suffix = uuid.uuid4().hex[:8]
    owner = User(
        username=f"owner_{suffix}",
        email=f"owner_{suffix}@test.vn",
        password_hash=get_password_hash("Pass123456!"),
        display_name="Fandom Owner",
        is_active=True,
    )
    async with AsyncSessionLocal() as db:
        db.add(owner)
        await db.commit()
        await db.refresh(owner)

        fandom = Fandom(
            name=f"Original Name {suffix}",
            slug=f"fandom-{suffix}",
            description="Original description",
            category="Âm nhạc",
            owner_id=owner.id,
            admission_mode="OPEN",
            rules_tos="Nội quy cũ",
        )
        db.add(fandom)
        await db.commit()
        await db.refresh(fandom)

    owner_token = create_access_token(data={"sub": str(owner.id), "username": owner.username})
    headers = {"Authorization": f"Bearer {owner_token}"}
    transport = ASGITransport(app=app)

    try:
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            update_payload = {
                "name": f"Updated Name {suffix}",
                "description": "Mô tả mới đã được cập nhật.",
                "category": "Thần tượng (Idol)",
                "admission_mode": "APPROVAL",
                "rules_tos": "Nội quy mới của Fandom: Tôn trọng idol và thành viên.",
                "avatar_url": "https://res.cloudinary.com/test/image/upload/avatar.jpg",
                "banner_url": "https://res.cloudinary.com/test/image/upload/banner.jpg",
                "illustration_urls": [
                    "https://res.cloudinary.com/test/image/upload/pic1.jpg",
                    "https://res.cloudinary.com/test/image/upload/pic2.jpg",
                    "https://res.cloudinary.com/test/video/upload/clip.mp4",
                ],
            }

            res = await client.patch(
                f"/api/v1/fandoms/{fandom.id}/profile",
                json=update_payload,
                headers=headers,
            )

            assert res.status_code == 200, res.text
            data = res.json()
            assert data["name"] == f"Updated Name {suffix}"
            assert data["description"] == "Mô tả mới đã được cập nhật."
            assert data["category"] == "Thần tượng (Idol)"
            assert data["admission_mode"] == "APPROVAL"
            assert data["rules_tos"] == "Nội quy mới của Fandom: Tôn trọng idol và thành viên."
            assert data["avatar_url"] == "https://res.cloudinary.com/test/image/upload/avatar.jpg"
            assert data["banner_url"] == "https://res.cloudinary.com/test/image/upload/banner.jpg"
            assert len(data["illustration_urls"]) == 3
            assert data["is_owner"] is True
    finally:
        await _cleanup([owner.id], [fandom.id])


@pytest.mark.asyncio
async def test_non_owner_cannot_update_fandom_profile():
    """Verifies that non-owners are rejected with 403 Forbidden."""
    suffix = uuid.uuid4().hex[:8]
    owner = User(
        username=f"real_owner_{suffix}",
        email=f"real_owner_{suffix}@test.vn",
        password_hash=get_password_hash("Pass123456!"),
        display_name="Real Owner",
        is_active=True,
    )
    stranger = User(
        username=f"stranger_{suffix}",
        email=f"stranger_{suffix}@test.vn",
        password_hash=get_password_hash("Pass123456!"),
        display_name="Stranger User",
        is_active=True,
    )
    async with AsyncSessionLocal() as db:
        db.add_all([owner, stranger])
        await db.commit()
        await db.refresh(owner)
        await db.refresh(stranger)

        fandom = Fandom(
            name=f"Fandom {suffix}",
            slug=f"fandom-{suffix}",
            owner_id=owner.id,
        )
        db.add(fandom)
        await db.commit()
        await db.refresh(fandom)

    stranger_token = create_access_token(data={"sub": str(stranger.id), "username": stranger.username})
    headers = {"Authorization": f"Bearer {stranger_token}"}
    transport = ASGITransport(app=app)

    try:
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            res = await client.patch(
                f"/api/v1/fandoms/{fandom.id}/profile",
                json={"name": "Hacked Name"},
                headers=headers,
            )
            assert res.status_code == 403
            assert "Chủ sở hữu" in res.json()["detail"]
    finally:
        await _cleanup([owner.id, stranger.id], [fandom.id])


@pytest.mark.asyncio
async def test_update_fandom_profile_validates_illustration_limits():
    """Verifies that exceeding 5 illustrations or providing >1 video triggers 400 Bad Request."""
    suffix = uuid.uuid4().hex[:8]
    owner = User(
        username=f"owner_{suffix}",
        email=f"owner_{suffix}@test.vn",
        password_hash=get_password_hash("Pass123456!"),
        display_name="Owner",
        is_active=True,
    )
    async with AsyncSessionLocal() as db:
        db.add(owner)
        await db.commit()
        await db.refresh(owner)

        fandom = Fandom(
            name=f"Fandom {suffix}",
            slug=f"fandom-{suffix}",
            owner_id=owner.id,
        )
        db.add(fandom)
        await db.commit()
        await db.refresh(fandom)

    owner_token = create_access_token(data={"sub": str(owner.id), "username": owner.username})
    headers = {"Authorization": f"Bearer {owner_token}"}
    transport = ASGITransport(app=app)

    try:
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            # Test > 5 illustrations
            res_too_many = await client.patch(
                f"/api/v1/fandoms/{fandom.id}/profile",
                json={"illustration_urls": [f"https://test.com/img{i}.jpg" for i in range(6)]},
                headers=headers,
            )
            assert res_too_many.status_code == 400
            assert "tối đa 5" in res_too_many.json()["detail"]

            # Test > 1 video
            res_too_many_videos = await client.patch(
                f"/api/v1/fandoms/{fandom.id}/profile",
                json={
                    "illustration_urls": [
                        "https://test.com/video1.mp4",
                        "https://test.com/video2.webm",
                    ]
                },
                headers=headers,
            )
            assert res_too_many_videos.status_code == 400
            assert "tối đa 1 video" in res_too_many_videos.json()["detail"]
    finally:
        await _cleanup([owner.id], [fandom.id])
