"""End-to-end scenario tests for Fandom channel creation, announcement publishing, and member chat."""

import uuid

import pytest

from app.core.database import AsyncSessionLocal, init_db
from app.core.permissions import DefaultMembershipPermissionAdapter
from app.core.security import get_password_hash
from app.modules.chat.schemas import MessageCreate
from app.modules.chat.service import ChannelService, MessageService
from app.modules.fandom.models import Fandom, FandomMember
from app.modules.identity.models import SystemRole, User


@pytest.mark.asyncio
async def test_owner_announcement_and_member_chat_end_to_end_scenario() -> None:
    """Verifies a complete workflow from default channel provisioning to owner announcement and member chat."""
    await init_db()
    suffix = uuid.uuid4().hex[:8]

    async with AsyncSessionLocal() as db:
        owner = User(
            email=f"owner_scen_{suffix}@fanspace.vn",
            username=f"owner_scen_{suffix}",
            password_hash=get_password_hash("Fanspace@2026"),
            display_name="Owner Scenario",
            system_role=SystemRole.USER.value,
            is_email_verified=True,
            is_active=True,
        )
        member = User(
            email=f"member_scen_{suffix}@fanspace.vn",
            username=f"member_scen_{suffix}",
            password_hash=get_password_hash("Fanspace@2026"),
            display_name="Member Scenario",
            system_role=SystemRole.USER.value,
            is_email_verified=True,
            is_active=True,
        )
        db.add_all([owner, member])
        await db.flush()

        fandom = Fandom(
            name=f"Scenario Fandom {suffix}",
            slug=f"scenario-fandom-{suffix}",
            description="Kịch bản kiểm thử toàn diện kênh giao tiếp",
            category="Âm nhạc",
            admission_mode="OPEN",
            is_public=True,
            member_count=2,
            owner_id=owner.id,
        )
        db.add(fandom)
        await db.flush()

        db.add_all(
            [
                FandomMember(fandom_id=fandom.id, user_id=owner.id, status="ACTIVE"),
                FandomMember(fandom_id=fandom.id, user_id=member.id, status="ACTIVE"),
            ]
        )
        default_channels = ChannelService.build_default_channels(fandom.id)
        db.add_all(default_channels)
        await db.commit()

        checker = DefaultMembershipPermissionAdapter(db)
        channels_out = await ChannelService.list_channels(
            db=db,
            fandom_identifier=fandom.slug,
            current_user=owner,
            perm_checker=checker,
        )
        ann_ch = next(c for c in channels_out.channels if c.is_announcement)
        chat_ch = next(
            c for c in channels_out.channels if c.type == "TEXT" and not c.is_announcement
        )

        # 1. Owner posts official announcement in #thông-báo
        ann_msg = await MessageService.send_message(
            db=db,
            channel_id=ann_ch.id,
            current_user=owner,
            data=MessageCreate(content="Thông báo chính thức từ Chủ Fandom!"),
            perm_checker=checker,
        )
        assert ann_msg.sender.is_owner is True

        # 2. Regular member chats in #chat-chung
        member_msg = await MessageService.send_message(
            db=db,
            channel_id=chat_ch.id,
            current_user=member,
            data=MessageCreate(content="Xin chào mọi người trong kênh chat chung!"),
            perm_checker=checker,
        )
        assert member_msg.sender.is_owner is False

        # 3. Member fetches message history in #chat-chung
        history = await MessageService.list_messages(
            db=db,
            channel_id=chat_ch.id,
            current_user=member,
            perm_checker=checker,
            limit=20,
        )
        assert len(history.messages) == 1
        assert history.messages[0].content == "Xin chào mọi người trong kênh chat chung!"
