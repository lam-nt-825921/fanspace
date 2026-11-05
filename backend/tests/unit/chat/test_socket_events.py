"""Tests for Socket.IO real-time message broadcast and channel room lifecycle."""

import uuid
from unittest.mock import AsyncMock, patch
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
from app.main import app, sio
from app.modules.chat.models import Channel, Message
from app.modules.fandom.models import Fandom
from app.modules.identity.models import User


async def _cleanup_socket_test_data(
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
async def test_posting_message_emits_new_message_to_socket_room():
    """Verifies that posting a message broadcasts `new_message` to the channel Socket.IO room."""
    suffix = uuid.uuid4().hex[:8]
    sender = User(
        username=f"sock_user_{suffix}",
        email=f"sock_user_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("Password123!"),
        display_name="Realtime User",
        is_active=True,
    )

    async with AsyncSessionLocal() as db:
        db.add(sender)
        await db.flush()

        fandom = Fandom(
            name=f"Socket Fandom {suffix}",
            slug=f"socket-fandom-{suffix}",
            description="Fandom kiểm thử Socket.IO",
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

        with patch.object(sio, "emit", new_callable=AsyncMock) as mock_emit:
            async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
                res = await ac.post(
                    f"/api/v1/channels/{channel_id}/messages",
                    headers={"Authorization": f"Bearer {token}"},
                    json={"content": "Tin nhắn phát trực tiếp qua Socket.IO!"},
                )
                assert res.status_code == 201, res.text

            mock_emit.assert_awaited_once()
            call_args = mock_emit.await_args
            assert call_args.args[0] == "new_message"
            assert call_args.args[1]["content"] == "Tin nhắn phát trực tiếp qua Socket.IO!"
            assert call_args.kwargs.get("room") == f"channel:{channel_id}"
    finally:
        app.dependency_overrides.pop(get_permission_checker, None)
        await _cleanup_socket_test_data([sender_id], [fandom_id], [channel_id])
