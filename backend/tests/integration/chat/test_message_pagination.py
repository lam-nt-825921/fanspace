"""Tests for cursor-based message history pagination and sender profile serialization."""

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


async def _cleanup_pagination_data(
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
async def test_message_cursor_pagination_and_ordering():
    """Verifies chronological ordering and before_id keyset pagination across 5 messages."""
    suffix = uuid.uuid4().hex[:8]
    sender = User(
        username=f"pag_user_{suffix}",
        email=f"pag_user_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("Password123!"),
        display_name="Pagination User",
        is_active=True,
    )

    async with AsyncSessionLocal() as db:
        db.add(sender)
        await db.flush()

        fandom = Fandom(
            name=f"Pag Fandom {suffix}",
            slug=f"pag-fandom-{suffix}",
            description="Fandom kiểm thử phân trang tin nhắn",
            category="Âm nhạc",
            admission_mode="OPEN",
            is_public=True,
            member_count=1,
            owner_id=sender.id,
        )
        db.add(fandom)
        await db.flush()

        channel = Channel(
            fandom_id=fandom.id,
            name="chat-chung",
            type="TEXT",
            is_announcement=False,
            position=0,
        )
        db.add(channel)
        await db.commit()

        sender_id = sender.id
        fandom_id = fandom.id
        channel_id = channel.id

    try:
        token = create_access_token(data={"sub": str(sender_id)})
        app.dependency_overrides[get_permission_checker] = lambda: MockPermissionChecker(
            granted={
                Permission.VIEW_CHANNEL,
                Permission.READ_MESSAGES,
                Permission.SEND_MESSAGES,
            }
        )

        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            for idx in range(1, 6):
                res = await ac.post(
                    f"/api/v1/channels/{channel_id}/messages",
                    headers={"Authorization": f"Bearer {token}"},
                    json={"content": f"Tin nhắn số {idx}"},
                )
                assert res.status_code == 201

            # 1. Fetch latest 3 messages -> returns messages 3, 4, 5 in chronological order.
            page1_res = await ac.get(
                f"/api/v1/channels/{channel_id}/messages?limit=3",
                headers={"Authorization": f"Bearer {token}"},
            )
            assert page1_res.status_code == 200, page1_res.text
            page1 = page1_res.json()
            assert [m["content"] for m in page1["messages"]] == [
                "Tin nhắn số 3",
                "Tin nhắn số 4",
                "Tin nhắn số 5",
            ]
            assert page1["has_more"] is True
            assert page1["next_cursor"] == page1["messages"][0]["id"]
            assert page1["messages"][0]["sender"]["display_name"] == "Pagination User"

            # 2. Fetch older messages before next_cursor -> returns messages 1, 2.
            cursor_id = page1["next_cursor"]
            page2_res = await ac.get(
                f"/api/v1/channels/{channel_id}/messages?limit=3&before_id={cursor_id}",
                headers={"Authorization": f"Bearer {token}"},
            )
            assert page2_res.status_code == 200, page2_res.text
            page2 = page2_res.json()
            assert [m["content"] for m in page2["messages"]] == [
                "Tin nhắn số 1",
                "Tin nhắn số 2",
            ]
            assert page2["has_more"] is False
    finally:
        app.dependency_overrides.pop(get_permission_checker, None)
        await _cleanup_pagination_data([sender_id], [fandom_id], [channel_id])
