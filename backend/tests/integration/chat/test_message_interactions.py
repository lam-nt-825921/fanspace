"""Integration tests for message reply previews, reaction toggling, and pinned message listing."""

import uuid

import pytest

from app.core.database import AsyncSessionLocal, init_db
from app.core.permissions import DefaultMembershipPermissionAdapter
from app.core.security import get_password_hash
from app.modules.chat.schemas import MessageCreate, MessageReactionRequest
from app.modules.chat.service import ChannelService, MessageService
from app.modules.fandom.models import Fandom, FandomMember
from app.modules.identity.models import SystemRole, User


@pytest.mark.asyncio
async def test_reply_quote_preview_and_pinned_messages_list() -> None:
    """Verifies that replying to a message populates reply_to preview and pinned messages can be listed."""
    await init_db()
    suffix = uuid.uuid4().hex[:8]

    async with AsyncSessionLocal() as db:
        owner = User(
            email=f"owner_int_{suffix}@fanspace.vn",
            username=f"owner_int_{suffix}",
            password_hash=get_password_hash("Fanspace@2026"),
            display_name="Owner Interactive",
            system_role=SystemRole.USER.value,
            is_email_verified=True,
            is_active=True,
        )
        db.add(owner)
        await db.flush()

        fandom = Fandom(
            name=f"Interactive Fandom {suffix}",
            slug=f"interactive-fandom-{suffix}",
            description="Kiểm thử trả lời và ghim tin nhắn",
            category="Âm nhạc",
            admission_mode="OPEN",
            is_public=True,
            member_count=1,
            owner_id=owner.id,
        )
        db.add(fandom)
        await db.flush()

        db.add(FandomMember(fandom_id=fandom.id, user_id=owner.id, status="ACTIVE"))
        channels = ChannelService.build_default_channels(fandom.id)
        db.add_all(channels)
        await db.commit()

        chat_channel = next(
            c for c in channels if c.type == "TEXT" and not c.is_announcement
        )
        checker = DefaultMembershipPermissionAdapter(db)

        # 1. Send root message
        root_msg = await MessageService.send_message(
            db=db,
            channel_id=chat_channel.id,
            current_user=owner,
            data=MessageCreate(content="Ai đi concert tối nay điểm danh nhé!"),
            perm_checker=checker,
        )

        # 2. Send reply message referencing root_msg.id
        reply_msg = await MessageService.send_message(
            db=db,
            channel_id=chat_channel.id,
            current_user=owner,
            data=MessageCreate(
                content="Mình có mặt ở khu Fandom Zone A!",
                reply_to_id=root_msg.id,
            ),
            perm_checker=checker,
        )
        assert reply_msg.reply_to_id == root_msg.id
        assert reply_msg.reply_to is not None
        assert reply_msg.reply_to.id == root_msg.id
        assert reply_msg.reply_to.content == "Ai đi concert tối nay điểm danh nhé!"
        assert reply_msg.reply_to.sender_display_name == "Owner Interactive"

        # 3. Toggle reaction twice (add then remove)
        r1 = await MessageService.toggle_reaction(
            db=db,
            channel_id=chat_channel.id,
            message_id=root_msg.id,
            current_user=owner,
            data=MessageReactionRequest(emoji="🔥"),
            perm_checker=checker,
        )
        assert str(owner.id) in r1.reactions.get("🔥", [])

        r2 = await MessageService.toggle_reaction(
            db=db,
            channel_id=chat_channel.id,
            message_id=root_msg.id,
            current_user=owner,
            data=MessageReactionRequest(emoji="🔥"),
            perm_checker=checker,
        )
        assert "🔥" not in r2.reactions

        # 4. Pin root_msg and list pinned messages in the channel
        await MessageService.toggle_pin_message(
            db=db,
            channel_id=chat_channel.id,
            message_id=root_msg.id,
            current_user=owner,
            perm_checker=checker,
        )
        pinned_list = await MessageService.list_pinned_messages(
            db=db,
            channel_id=chat_channel.id,
            current_user=owner,
            perm_checker=checker,
        )
        assert len(pinned_list) == 1
        assert pinned_list[0].id == root_msg.id
