"""Integration tests for Redis-backed channel Slow-mode enforcement and BYPASS_SLOWMODE exemption."""

import uuid

import pytest
from fastapi import HTTPException

from app.core.database import AsyncSessionLocal, init_db
from app.core.permissions import MockPermissionChecker, Permission
from app.core.redis import get_redis_client
from app.core.security import get_password_hash
from app.modules.chat.models import Channel
from app.modules.chat.schemas import MessageCreate
from app.modules.chat.service import MessageService
from app.modules.fandom.models import Fandom
from app.modules.identity.models import SystemRole, User


@pytest.mark.asyncio
async def test_channel_slow_mode_rate_limits_regular_member_and_exempts_bypass_permission() -> None:
    """Verifies that slow_mode_seconds blocks rapid consecutive messages unless BYPASS_SLOWMODE is granted."""
    await init_db()
    redis = get_redis_client()
    suffix = uuid.uuid4().hex[:8]

    async with AsyncSessionLocal() as db:
        user = User(
            email=f"slow_{suffix}@fanspace.vn",
            username=f"slow_{suffix}",
            password_hash=get_password_hash("Fanspace@2026"),
            display_name="Slow Mode User",
            system_role=SystemRole.USER.value,
            is_email_verified=True,
            is_active=True,
        )
        db.add(user)
        await db.flush()

        fandom = Fandom(
            name=f"Slow Mode Fandom {suffix}",
            slug=f"slow-fandom-{suffix}",
            description="Kiểm thử chế độ chậm",
            category="Game & Esports",
            admission_mode="OPEN",
            is_public=True,
            member_count=1,
            owner_id=user.id,
        )
        db.add(fandom)
        await db.flush()

        slow_channel = Channel(
            fandom_id=fandom.id,
            name="chat-cham",
            type="TEXT",
            topic="Kênh giới hạn 15 giây mỗi tin nhắn",
            position=0,
            is_announcement=False,
            slow_mode_seconds=15,
        )
        db.add(slow_channel)
        await db.commit()
        await db.refresh(slow_channel)

        regular_checker = MockPermissionChecker(
            granted={
                Permission.VIEW_CHANNEL,
                Permission.READ_MESSAGES,
                Permission.SEND_MESSAGES,
            }
        )
        bypass_checker = MockPermissionChecker(
            granted={
                Permission.VIEW_CHANNEL,
                Permission.READ_MESSAGES,
                Permission.SEND_MESSAGES,
                Permission.BYPASS_SLOWMODE,
            }
        )

        # 1. First message from regular member succeeds and sets Redis TTL
        first_msg = await MessageService.send_message(
            db=db,
            channel_id=slow_channel.id,
            current_user=user,
            data=MessageCreate(content="Tin nhắn thứ nhất"),
            perm_checker=regular_checker,
            redis=redis,
        )
        assert first_msg.content == "Tin nhắn thứ nhất"

        # 2. Immediate second message from regular member is blocked with 429 Too Many Requests
        with pytest.raises(HTTPException) as exc_slow:
            await MessageService.send_message(
                db=db,
                channel_id=slow_channel.id,
                current_user=user,
                data=MessageCreate(content="Tin nhắn thứ hai quá nhanh"),
                perm_checker=regular_checker,
                redis=redis,
            )
        assert exc_slow.value.status_code == 429

        # 3. User with BYPASS_SLOWMODE sends immediately without waiting for cooldown
        bypass_msg = await MessageService.send_message(
            db=db,
            channel_id=slow_channel.id,
            current_user=user,
            data=MessageCreate(content="Tin nhắn ưu tiên bỏ qua chế độ chậm"),
            perm_checker=bypass_checker,
            redis=redis,
        )
        assert bypass_msg.content == "Tin nhắn ưu tiên bỏ qua chế độ chậm"
