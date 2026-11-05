"""Tests for decoupled message sending and reading permissions via MockPermissionChecker.

Verifies that message endpoints enforce:
1. must_have: VIEW_CHANNEL + READ_MESSAGES for reading history.
2. must_have: VIEW_CHANNEL + SEND_MESSAGES for posting messages.
3. may_have: SEND_ANNOUNCEMENT required when channel.is_announcement is True.
4. may_have: ATTACH_FILES required when message includes attachments.
5. may_have: EMBED_LINKS required when message content includes URLs.
"""

import uuid
import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import delete

from app.core.database import AsyncSessionLocal
from app.core.permissions import (
    MockPermissionChecker,
    Permission,
    get_permission_checker,
)
from app.core.security import create_access_token, get_password_hash
from app.main import app
from app.modules.chat.models import Channel, Message
from app.modules.fandom.models import Fandom
from app.modules.identity.models import User


async def _cleanup_msg_perm_data(
    user_ids: list[uuid.UUID],
    fandom_ids: list[uuid.UUID],
    channel_ids: list[uuid.UUID],
) -> None:
    """Removes test messages, channels, fandoms, and users."""
    async with AsyncSessionLocal() as db:
        if channel_ids:
            await db.execute(delete(Message).where(Message.channel_id.in_(channel_ids)))
        if fandom_ids:
            await db.execute(delete(Channel).where(Channel.fandom_id.in_(fandom_ids)))
            await db.execute(delete(Fandom).where(Fandom.id.in_(fandom_ids)))
        if user_ids:
            await db.execute(delete(User).where(User.id.in_(user_ids)))
        await db.commit()


@pytest.mark.asyncio
async def test_message_send_and_read_with_mock_permission_combinations():
    """Verifies must_have and conditional may_have checks on text and announcement channels."""
    suffix = uuid.uuid4().hex[:8]
    user = User(
        username=f"msg_user_{suffix}",
        email=f"msg_user_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("Password123!"),
        display_name="Chat Tester",
        is_active=True,
    )

    async with AsyncSessionLocal() as db:
        db.add(user)
        await db.flush()

        fandom = Fandom(
            name=f"Chat Perm Fandom {suffix}",
            slug=f"chat-perm-fandom-{suffix}",
            description="Fandom kiểm thử quyền nhắn tin",
            category="Âm nhạc",
            admission_mode="OPEN",
            is_public=True,
            member_count=1,
            owner_id=user.id,
        )
        db.add(fandom)
        await db.flush()

        text_channel = Channel(
            fandom_id=fandom.id,
            name="chat-chung",
            type="TEXT",
            is_announcement=False,
            position=0,
        )
        ann_channel = Channel(
            fandom_id=fandom.id,
            name="thong-bao",
            type="TEXT",
            is_announcement=True,
            position=1,
        )
        db.add_all([text_channel, ann_channel])
        await db.commit()

        user_id = user.id
        fandom_id = fandom.id
        text_ch_id = text_channel.id
        ann_ch_id = ann_channel.id

    try:
        token = create_access_token(data={"sub": str(user_id)})

        # 1. Missing READ_MESSAGES -> GET messages returns 403.
        app.dependency_overrides[get_permission_checker] = lambda: MockPermissionChecker(
            granted={Permission.VIEW_CHANNEL}
        )
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            read_denied = await ac.get(
                f"/api/v1/channels/{text_ch_id}/messages",
                headers={"Authorization": f"Bearer {token}"},
            )
            assert read_denied.status_code == 403

        # 2. Has VIEW_CHANNEL + SEND_MESSAGES only (no ATTACH_FILES, no EMBED_LINKS, no SEND_ANNOUNCEMENT).
        app.dependency_overrides[get_permission_checker] = lambda: MockPermissionChecker(
            granted={
                Permission.VIEW_CHANNEL,
                Permission.READ_MESSAGES,
                Permission.SEND_MESSAGES,
            }
        )
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            # Plain text message on regular channel succeeds.
            plain_ok = await ac.post(
                f"/api/v1/channels/{text_ch_id}/messages",
                headers={"Authorization": f"Bearer {token}"},
                json={"content": "Xin chào mọi người trong Fandom!"},
            )
            assert plain_ok.status_code == 201, plain_ok.text
            assert plain_ok.json()["content"] == "Xin chào mọi người trong Fandom!"

            # Sending attachment without ATTACH_FILES fails with 403.
            attach_denied = await ac.post(
                f"/api/v1/channels/{text_ch_id}/messages",
                headers={"Authorization": f"Bearer {token}"},
                json={
                    "content": "Ảnh sự kiện",
                    "attachments": [{"url": "https://res.cloudinary.com/demo/image/upload/sample.jpg", "type": "IMAGE"}],
                },
            )
            assert attach_denied.status_code == 403
            assert "đính kèm" in attach_denied.json()["detail"].lower()

            # Sending link without EMBED_LINKS fails with 403.
            link_denied = await ac.post(
                f"/api/v1/channels/{text_ch_id}/messages",
                headers={"Authorization": f"Bearer {token}"},
                json={"content": "Xem video tại https://example.com/live"},
            )
            assert link_denied.status_code == 403
            assert "liên kết" in link_denied.json()["detail"].lower()

            # Posting on announcement channel without SEND_ANNOUNCEMENT fails with 403.
            ann_denied = await ac.post(
                f"/api/v1/channels/{ann_ch_id}/messages",
                headers={"Authorization": f"Bearer {token}"},
                json={"content": "Thông báo giả mạo"},
            )
            assert ann_denied.status_code == 403
            assert "thông báo" in ann_denied.json()["detail"].lower()

        # 3. Granting ATTACH_FILES, EMBED_LINKS, and SEND_ANNOUNCEMENT unlocks all three capabilities.
        app.dependency_overrides[get_permission_checker] = lambda: MockPermissionChecker(
            granted={
                Permission.VIEW_CHANNEL,
                Permission.READ_MESSAGES,
                Permission.SEND_MESSAGES,
                Permission.ATTACH_FILES,
                Permission.EMBED_LINKS,
                Permission.SEND_ANNOUNCEMENT,
            }
        )
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            rich_ok = await ac.post(
                f"/api/v1/channels/{text_ch_id}/messages",
                headers={"Authorization": f"Bearer {token}"},
                json={
                    "content": "Link chính thức https://fanspace.vn",
                    "attachments": [{"url": "https://res.cloudinary.com/demo/image/upload/sample.jpg", "type": "IMAGE"}],
                },
            )
            assert rich_ok.status_code == 201, rich_ok.text
            assert len(rich_ok.json()["attachments"]) == 1

            ann_ok = await ac.post(
                f"/api/v1/channels/{ann_ch_id}/messages",
                headers={"Authorization": f"Bearer {token}"},
                json={"content": "Thông báo lịch diễn chính thức tuần này!"},
            )
            assert ann_ok.status_code == 201, ann_ok.text
    finally:
        app.dependency_overrides.pop(get_permission_checker, None)
        await _cleanup_msg_perm_data([user_id], [fandom_id], [text_ch_id, ann_ch_id])
