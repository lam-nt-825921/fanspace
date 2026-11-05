"""Unit tests for message editing, recall/moderation, pinning, and reactions using MockPermissionChecker."""

import uuid

import pytest
from fastapi import HTTPException

from app.core.database import AsyncSessionLocal, init_db
from app.core.permissions import MockPermissionChecker, Permission
from app.core.security import get_password_hash
from app.modules.chat.schemas import (
    MessageCreate,
    MessageReactionRequest,
    MessageUpdate,
)
from app.modules.chat.service import ChannelService, MessageService
from app.modules.fandom.models import Fandom
from app.modules.identity.models import SystemRole, User


@pytest.mark.asyncio
async def test_edit_recall_pin_and_react_with_mock_permissions() -> None:
    """Verifies declarative permission enforcement for edit, recall, pin, and reaction operations."""
    await init_db()
    suffix = uuid.uuid4().hex[:8]

    async with AsyncSessionLocal() as db:
        owner = User(
            email=f"owner_mod_{suffix}@fanspace.vn",
            username=f"owner_mod_{suffix}",
            password_hash=get_password_hash("Fanspace@2026"),
            display_name="Owner Mod",
            system_role=SystemRole.USER.value,
            is_email_verified=True,
            is_active=True,
        )
        author = User(
            email=f"author_mod_{suffix}@fanspace.vn",
            username=f"author_mod_{suffix}",
            password_hash=get_password_hash("Fanspace@2026"),
            display_name="Author Member",
            system_role=SystemRole.USER.value,
            is_email_verified=True,
            is_active=True,
        )
        other_user = User(
            email=f"other_mod_{suffix}@fanspace.vn",
            username=f"other_mod_{suffix}",
            password_hash=get_password_hash("Fanspace@2026"),
            display_name="Other Member",
            system_role=SystemRole.USER.value,
            is_email_verified=True,
            is_active=True,
        )
        db.add_all([owner, author, other_user])
        await db.flush()

        fandom = Fandom(
            name=f"Moderation Test Fandom {suffix}",
            slug=f"mod-fandom-{suffix}",
            description="Kiểm thử tương tác và kiểm duyệt tin nhắn",
            category="Âm nhạc",
            admission_mode="OPEN",
            is_public=True,
            member_count=3,
            owner_id=owner.id,
        )
        db.add(fandom)
        await db.flush()

        channels = ChannelService.build_default_channels(fandom.id)
        db.add_all(channels)
        await db.commit()

        chat_channel = next(
            c for c in channels if c.type == "TEXT" and not c.is_announcement
        )

        member_checker = MockPermissionChecker(
            granted={
                Permission.VIEW_CHANNEL,
                Permission.READ_MESSAGES,
                Permission.SEND_MESSAGES,
            }
        )
        moderator_checker = MockPermissionChecker(
            granted={
                Permission.VIEW_CHANNEL,
                Permission.READ_MESSAGES,
                Permission.SEND_MESSAGES,
                Permission.MODERATE_CHAT,
            }
        )

        # 1. Author sends an initial message
        msg = await MessageService.send_message(
            db=db,
            channel_id=chat_channel.id,
            current_user=author,
            data=MessageCreate(content="Nội dung gốc ban đầu"),
            perm_checker=member_checker,
        )
        assert msg.is_edited is False

        # 2. Non-author cannot edit author's message -> 403 Forbidden
        with pytest.raises(HTTPException) as exc_edit:
            await MessageService.edit_message(
                db=db,
                channel_id=chat_channel.id,
                message_id=msg.id,
                current_user=other_user,
                data=MessageUpdate(content="Cố tình sửa tin người khác"),
                perm_checker=member_checker,
            )
        assert exc_edit.value.status_code == 403

        # 3. Author edits their own message -> succeeds
        edited = await MessageService.edit_message(
            db=db,
            channel_id=chat_channel.id,
            message_id=msg.id,
            current_user=author,
            data=MessageUpdate(content="Nội dung đã chỉnh sửa"),
            perm_checker=member_checker,
        )
        assert edited.content == "Nội dung đã chỉnh sửa"
        assert edited.is_edited is True

        # 4. Member without MODERATE_CHAT cannot pin message -> 403 Forbidden
        with pytest.raises(HTTPException) as exc_pin:
            await MessageService.toggle_pin_message(
                db=db,
                channel_id=chat_channel.id,
                message_id=msg.id,
                current_user=other_user,
                perm_checker=member_checker,
            )
        assert exc_pin.value.status_code == 403

        # 5. Moderator with MODERATE_CHAT pins the message -> succeeds
        pinned = await MessageService.toggle_pin_message(
            db=db,
            channel_id=chat_channel.id,
            message_id=msg.id,
            current_user=other_user,
            perm_checker=moderator_checker,
        )
        assert pinned.is_pinned is True

        # 6. Member toggles emoji reaction ❤️
        reacted = await MessageService.toggle_reaction(
            db=db,
            channel_id=chat_channel.id,
            message_id=msg.id,
            current_user=other_user,
            data=MessageReactionRequest(emoji="❤️"),
            perm_checker=member_checker,
        )
        assert str(other_user.id) in reacted.reactions.get("❤️", [])

        # 7. Non-author without MODERATE_CHAT cannot recall author's message -> 403 Forbidden
        with pytest.raises(HTTPException) as exc_recall:
            await MessageService.recall_message(
                db=db,
                channel_id=chat_channel.id,
                message_id=msg.id,
                current_user=other_user,
                perm_checker=member_checker,
            )
        assert exc_recall.value.status_code == 403

        # 8. Moderator with MODERATE_CHAT recalls author's message -> succeeds
        recalled = await MessageService.recall_message(
            db=db,
            channel_id=chat_channel.id,
            message_id=msg.id,
            current_user=other_user,
            perm_checker=moderator_checker,
        )
        assert recalled.is_recalled is True
        assert recalled.is_pinned is False
