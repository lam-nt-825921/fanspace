"""Business logic service for fandom communication channels.

Each operation declares its authorization expectations via `PermissionSpec` and
verifies them through the injected `IPermissionChecker` port without coupling to
RBAC storage mechanisms.
"""

import uuid
from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.permissions import (
    ALL_PERMISSIONS_SET,
    IPermissionChecker,
    Permission,
    PermissionSpec,
)
from app.modules.chat.models import Channel
from app.modules.chat.schemas import (
    ChannelCreate,
    ChannelDeleteResponse,
    ChannelOut,
    ChannelUpdate,
    FandomChannelsListResponse,
)
from app.modules.fandom.models import Fandom
from app.modules.identity.models import User


LIST_CHANNELS_SPEC = PermissionSpec.of(
    must_have={Permission.VIEW_CHANNEL},
    may_have={
        Permission.READ_MESSAGES,
        Permission.SEND_MESSAGES,
        Permission.SEND_ANNOUNCEMENT,
        Permission.ATTACH_FILES,
        Permission.EMBED_LINKS,
        Permission.MODERATE_CHAT,
        Permission.BYPASS_SLOWMODE,
        Permission.MANAGE_CHANNELS,
        Permission.VOICE_CONNECT,
        Permission.VOICE_SPEAK,
    },
)

MANAGE_CHANNEL_SPEC = PermissionSpec.of(
    must_have={Permission.VIEW_CHANNEL, Permission.MANAGE_CHANNELS},
)


class ChannelService:
    """Service orchestrating channel provisioning, listing, and lifecycle updates."""

    @staticmethod
    async def resolve_fandom(
        db: AsyncSession,
        fandom_identifier: str,
    ) -> Fandom:
        """Resolves a Fandom entity by either its UUID string or its unique slug.

        Args:
            db: Active asynchronous database session.
            fandom_identifier: UUID or URL slug of the target fandom.

        Returns:
            Fandom: Resolved ORM entity.

        Raises:
            HTTPException: 404 Not Found if the fandom does not exist.
        """
        cleaned = fandom_identifier.strip()
        try:
            parsed_uuid = uuid.UUID(cleaned)
            stmt = select(Fandom).where(Fandom.id == parsed_uuid)
        except ValueError:
            stmt = select(Fandom).where(Fandom.slug == cleaned.lower())

        result = await db.execute(stmt)
        fandom = result.scalar_one_or_none()
        if not fandom:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Không tìm thấy không gian Fandom yêu cầu.",
            )
        return fandom

    @staticmethod
    def build_default_channels(fandom_id: uuid.UUID) -> list[Channel]:
        """Builds the default set of channels for a newly provisioned fandom.

        Args:
            fandom_id: Target fandom UUID.

        Returns:
            list[Channel]: Uncommitted list of three default channels.
        """
        return [
            Channel(
                fandom_id=fandom_id,
                name="thông-báo",
                type="TEXT",
                topic="Kênh thông báo chính thức từ Chủ Fandom và Ban quản trị",
                position=0,
                is_announcement=True,
                is_membership_only=False,
                slow_mode_seconds=0,
            ),
            Channel(
                fandom_id=fandom_id,
                name="chat-chung",
                type="TEXT",
                topic="Không gian trò chuyện và giao lưu chung của cộng đồng",
                position=1,
                is_announcement=False,
                is_membership_only=False,
                slow_mode_seconds=0,
            ),
            Channel(
                fandom_id=fandom_id,
                name="Phòng Thoại Chung",
                type="VOICE",
                topic="Phòng giao lưu âm thanh trực tiếp",
                position=2,
                is_announcement=False,
                is_membership_only=False,
                slow_mode_seconds=0,
                voice_room_type="OPEN_MIC",
            ),
        ]

    @classmethod
    async def ensure_default_channels(
        cls,
        db: AsyncSession,
        fandom_id: uuid.UUID,
    ) -> list[Channel]:
        """Returns existing channels for a fandom, seeding defaults if none exist.

        Args:
            db: Active database session.
            fandom_id: Target fandom UUID.

        Returns:
            list[Channel]: Ordered list of channels belonging to the fandom.
        """
        stmt = (
            select(Channel)
            .where(Channel.fandom_id == fandom_id)
            .order_by(Channel.position.asc(), Channel.created_at.asc())
        )
        result = await db.execute(stmt)
        channels = list(result.scalars().all())
        if channels:
            return channels

        defaults = cls.build_default_channels(fandom_id)
        db.add_all(defaults)
        await db.commit()
        for ch in defaults:
            await db.refresh(ch)
        return defaults

    @classmethod
    async def list_channels(
        cls,
        db: AsyncSession,
        fandom_identifier: str,
        current_user: User,
        perm_checker: IPermissionChecker,
    ) -> FandomChannelsListResponse:
        """Lists all channels visible to `current_user` along with per-channel permissions.

        Args:
            db: Active database session.
            fandom_identifier: Fandom UUID or slug.
            current_user: Authenticated caller.
            perm_checker: Permission evaluation adapter.

        Returns:
            FandomChannelsListResponse: Fandom metadata and accessible channels.
        """
        fandom = await cls.resolve_fandom(db, fandom_identifier)
        fandom_eval = await perm_checker.verify(
            user_id=current_user.id,
            fandom_id=fandom.id,
            channel_id=None,
            spec=LIST_CHANNELS_SPEC,
            error_detail="Bạn cần là thành viên chính thức của Fandom để truy cập danh sách kênh.",
        )

        channels = await cls.ensure_default_channels(db, fandom.id)
        accessible_channels: list[ChannelOut] = []

        for channel in channels:
            raw_channel_perms = await perm_checker.resolve_permissions(
                user_id=current_user.id,
                fandom_id=fandom.id,
                channel_id=channel.id,
            )
            effective_perms = (
                ALL_PERMISSIONS_SET
                if Permission.ADMINISTRATOR in raw_channel_perms
                else frozenset(raw_channel_perms)
            )
            if Permission.VIEW_CHANNEL not in effective_perms:
                continue

            accessible_channels.append(
                ChannelOut(
                    id=channel.id,
                    fandom_id=channel.fandom_id,
                    name=channel.name,
                    type=channel.type,
                    topic=channel.topic,
                    position=channel.position,
                    is_announcement=channel.is_announcement,
                    is_membership_only=channel.is_membership_only,
                    required_role_id=channel.required_role_id,
                    slow_mode_seconds=channel.slow_mode_seconds,
                    voice_room_type=channel.voice_room_type,
                    created_at=channel.created_at,
                    my_permissions=sorted(p.value for p in effective_perms),
                )
            )

        return FandomChannelsListResponse(
            fandom_id=fandom.id,
            slug=fandom.slug,
            my_fandom_permissions=fandom_eval.to_sorted_list(),
            channels=accessible_channels,
        )

    @classmethod
    async def create_channel(
        cls,
        db: AsyncSession,
        fandom_identifier: str,
        current_user: User,
        data: ChannelCreate,
        perm_checker: IPermissionChecker,
    ) -> ChannelOut:
        """Creates a new communication channel inside a fandom.

        Args:
            db: Active database session.
            fandom_identifier: Fandom UUID or slug.
            current_user: Authenticated caller.
            data: Channel creation payload.
            perm_checker: Permission evaluation adapter.

        Returns:
            ChannelOut: Newly created channel with caller's effective permissions.
        """
        fandom = await cls.resolve_fandom(db, fandom_identifier)
        await perm_checker.verify(
            user_id=current_user.id,
            fandom_id=fandom.id,
            channel_id=None,
            spec=MANAGE_CHANNEL_SPEC,
            error_detail="Bạn không có quyền quản lý (tạo mới) kênh trong Fandom này.",
        )

        max_pos_res = await db.execute(
            select(func.coalesce(func.max(Channel.position), -1)).where(
                Channel.fandom_id == fandom.id
            )
        )
        next_position = int(max_pos_res.scalar_one()) + 1

        voice_type = data.voice_room_type
        if data.type == "VOICE" and not voice_type:
            voice_type = "OPEN_MIC"
        elif data.type == "TEXT":
            voice_type = None

        channel = Channel(
            fandom_id=fandom.id,
            name=data.name,
            type=data.type,
            topic=data.topic.strip() if data.topic else None,
            position=next_position,
            is_announcement=data.is_announcement if data.type == "TEXT" else False,
            is_membership_only=data.is_membership_only,
            required_role_id=data.required_role_id,
            slow_mode_seconds=data.slow_mode_seconds if data.type == "TEXT" else 0,
            voice_room_type=voice_type,
        )
        db.add(channel)
        await db.commit()
        await db.refresh(channel)

        raw_perms = await perm_checker.resolve_permissions(
            user_id=current_user.id,
            fandom_id=fandom.id,
            channel_id=channel.id,
        )
        effective_perms = (
            ALL_PERMISSIONS_SET
            if Permission.ADMINISTRATOR in raw_perms
            else frozenset(raw_perms)
        )

        return ChannelOut(
            id=channel.id,
            fandom_id=channel.fandom_id,
            name=channel.name,
            type=channel.type,
            topic=channel.topic,
            position=channel.position,
            is_announcement=channel.is_announcement,
            is_membership_only=channel.is_membership_only,
            required_role_id=channel.required_role_id,
            slow_mode_seconds=channel.slow_mode_seconds,
            voice_room_type=channel.voice_room_type,
            created_at=channel.created_at,
            my_permissions=sorted(p.value for p in effective_perms),
        )

    @classmethod
    async def update_channel(
        cls,
        db: AsyncSession,
        fandom_identifier: str,
        channel_id: uuid.UUID,
        current_user: User,
        data: ChannelUpdate,
        perm_checker: IPermissionChecker,
    ) -> ChannelOut:
        """Updates an existing fandom channel's configuration.

        Args:
            db: Active database session.
            fandom_identifier: Fandom UUID or slug.
            channel_id: Target channel UUID.
            current_user: Authenticated caller.
            data: Partial update fields.
            perm_checker: Permission evaluation adapter.

        Returns:
            ChannelOut: Updated channel representation.
        """
        fandom = await cls.resolve_fandom(db, fandom_identifier)
        await perm_checker.verify(
            user_id=current_user.id,
            fandom_id=fandom.id,
            channel_id=channel_id,
            spec=MANAGE_CHANNEL_SPEC,
            error_detail="Bạn không có quyền chỉnh sửa cấu hình kênh này.",
        )

        res = await db.execute(
            select(Channel).where(
                Channel.id == channel_id,
                Channel.fandom_id == fandom.id,
            )
        )
        channel = res.scalar_one_or_none()
        if not channel:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Không tìm thấy kênh yêu cầu trong Fandom này.",
            )

        if data.name is not None:
            cleaned_name = data.name.strip()
            if len(cleaned_name) < 2:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Tên kênh phải có ít nhất 2 ký tự.",
                )
            channel.name = cleaned_name

        if data.topic is not None:
            channel.topic = data.topic.strip() if data.topic.strip() else None

        if data.position is not None:
            channel.position = data.position

        if data.is_announcement is not None and channel.type == "TEXT":
            channel.is_announcement = data.is_announcement

        if data.is_membership_only is not None:
            channel.is_membership_only = data.is_membership_only

        if data.required_role_id is not None:
            channel.required_role_id = data.required_role_id

        if data.slow_mode_seconds is not None and channel.type == "TEXT":
            channel.slow_mode_seconds = data.slow_mode_seconds

        if data.voice_room_type is not None and channel.type == "VOICE":
            channel.voice_room_type = data.voice_room_type

        await db.commit()
        await db.refresh(channel)

        raw_perms = await perm_checker.resolve_permissions(
            user_id=current_user.id,
            fandom_id=fandom.id,
            channel_id=channel.id,
        )
        effective_perms = (
            ALL_PERMISSIONS_SET
            if Permission.ADMINISTRATOR in raw_perms
            else frozenset(raw_perms)
        )

        return ChannelOut(
            id=channel.id,
            fandom_id=channel.fandom_id,
            name=channel.name,
            type=channel.type,
            topic=channel.topic,
            position=channel.position,
            is_announcement=channel.is_announcement,
            is_membership_only=channel.is_membership_only,
            required_role_id=channel.required_role_id,
            slow_mode_seconds=channel.slow_mode_seconds,
            voice_room_type=channel.voice_room_type,
            created_at=channel.created_at,
            my_permissions=sorted(p.value for p in effective_perms),
        )

    @classmethod
    async def delete_channel(
        cls,
        db: AsyncSession,
        fandom_identifier: str,
        channel_id: uuid.UUID,
        current_user: User,
        perm_checker: IPermissionChecker,
    ) -> ChannelDeleteResponse:
        """Deletes a channel from a fandom while preventing deletion of the last channel.

        Args:
            db: Active database session.
            fandom_identifier: Fandom UUID or slug.
            channel_id: Target channel UUID to delete.
            current_user: Authenticated caller.
            perm_checker: Permission evaluation adapter.

        Returns:
            ChannelDeleteResponse: Confirmation of channel removal.
        """
        fandom = await cls.resolve_fandom(db, fandom_identifier)
        await perm_checker.verify(
            user_id=current_user.id,
            fandom_id=fandom.id,
            channel_id=channel_id,
            spec=MANAGE_CHANNEL_SPEC,
            error_detail="Bạn không có quyền xóa kênh trong Fandom này.",
        )

        res = await db.execute(
            select(Channel).where(
                Channel.id == channel_id,
                Channel.fandom_id == fandom.id,
            )
        )
        channel = res.scalar_one_or_none()
        if not channel:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Không tìm thấy kênh cần xóa.",
            )

        count_res = await db.execute(
            select(func.count(Channel.id)).where(Channel.fandom_id == fandom.id)
        )
        total_channels = int(count_res.scalar_one())
        if total_channels <= 1:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Không thể xóa kênh duy nhất còn lại trong Fandom.",
            )

        channel_name = channel.name
        await db.delete(channel)
        await db.commit()

        return ChannelDeleteResponse(
            success=True,
            message=f"Đã xóa kênh '{channel_name}' thành công.",
            deleted_channel_id=channel_id,
        )


import re
from sqlalchemy import tuple_
from sqlalchemy.orm import selectinload

from app.modules.chat.models import Message
from app.modules.chat.schemas import (
    MessageCreate,
    MessageListResponse,
    MessageOut,
    MessageSenderOut,
)


READ_MESSAGES_SPEC = PermissionSpec.of(
    must_have={Permission.VIEW_CHANNEL, Permission.READ_MESSAGES},
)

SEND_MESSAGE_SPEC = PermissionSpec.of(
    must_have={Permission.VIEW_CHANNEL, Permission.SEND_MESSAGES},
    may_have={
        Permission.SEND_ANNOUNCEMENT,
        Permission.ATTACH_FILES,
        Permission.EMBED_LINKS,
        Permission.BYPASS_SLOWMODE,
        Permission.MODERATE_CHAT,
    },
)

_URL_PATTERN = re.compile(r"https?://\S+", re.IGNORECASE)


class MessageService:
    """Service orchestrating channel message history retrieval and real-time message creation."""

    @staticmethod
    async def resolve_channel_and_fandom(
        db: AsyncSession,
        channel_id: uuid.UUID,
    ) -> tuple[Channel, Fandom]:
        """Resolves a Channel and its parent Fandom by `channel_id`.

        Args:
            db: Active asynchronous database session.
            channel_id: Target channel UUID.

        Returns:
            tuple[Channel, Fandom]: Resolved channel and parent fandom entities.

        Raises:
            HTTPException: 404 Not Found if the channel or fandom does not exist.
        """
        stmt = (
            select(Channel)
            .options(selectinload(Channel.fandom))
            .where(Channel.id == channel_id)
        )
        result = await db.execute(stmt)
        channel = result.scalar_one_or_none()
        if not channel or not channel.fandom:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Không tìm thấy kênh giao tiếp yêu cầu.",
            )
        return channel, channel.fandom

    @staticmethod
    def serialize_message(
        message: Message,
        sender: User,
        fandom_owner_id: uuid.UUID,
    ) -> MessageOut:
        """Converts a `Message` ORM entity and its `User` sender into `MessageOut`.

        Args:
            message: Message ORM instance.
            sender: User ORM instance who authored the message.
            fandom_owner_id: Owner UUID of the parent fandom.

        Returns:
            MessageOut: Serialized message DTO.
        """
        return MessageOut(
            id=message.id,
            channel_id=message.channel_id,
            fandom_id=message.channel.fandom_id if message.channel else uuid.UUID(int=0),
            sender_id=message.sender_id,
            sender=MessageSenderOut(
                id=sender.id,
                username=sender.username,
                display_name=sender.display_name or sender.username,
                avatar_url=sender.avatar_url,
                is_owner=(sender.id == fandom_owner_id),
            ),
            content=message.content,
            attachments=list(message.attachments or []),
            reply_to_id=message.reply_to_id,
            is_pinned=message.is_pinned,
            reactions=dict(message.reactions or {}),
            is_edited=message.is_edited,
            is_recalled=message.is_recalled,
            created_at=message.created_at,
            updated_at=message.updated_at,
        )

    @classmethod
    async def list_messages(
        cls,
        db: AsyncSession,
        channel_id: uuid.UUID,
        current_user: User,
        perm_checker: IPermissionChecker,
        before_id: uuid.UUID | None = None,
        limit: int = 30,
    ) -> MessageListResponse:
        """Retrieves chronological message history using cursor-based keyset pagination.

        Args:
            db: Active database session.
            channel_id: Target channel UUID.
            current_user: Authenticated caller.
            perm_checker: Permission evaluation adapter.
            before_id: Optional cursor message UUID to fetch older messages before.
            limit: Maximum number of messages to return (1..100).

        Returns:
            MessageListResponse: Chronologically ordered slice of messages and cursor metadata.
        """
        channel, fandom = await cls.resolve_channel_and_fandom(db, channel_id)
        await perm_checker.verify(
            user_id=current_user.id,
            fandom_id=fandom.id,
            channel_id=channel.id,
            spec=READ_MESSAGES_SPEC,
            error_detail="Bạn không có quyền đọc tin nhắn trong kênh này.",
        )

        safe_limit = max(1, min(limit, 100))
        stmt = (
            select(Message)
            .options(selectinload(Message.sender), selectinload(Message.channel))
            .where(Message.channel_id == channel.id)
        )

        if before_id is not None:
            anchor_res = await db.execute(
                select(Message).where(
                    Message.id == before_id,
                    Message.channel_id == channel.id,
                )
            )
            anchor = anchor_res.scalar_one_or_none()
            if anchor is not None:
                stmt = stmt.where(
                    tuple_(Message.created_at, Message.id)
                    < (anchor.created_at, anchor.id)
                )

        stmt = stmt.order_by(Message.created_at.desc(), Message.id.desc()).limit(
            safe_limit + 1
        )
        result = await db.execute(stmt)
        rows = list(result.scalars().all())

        has_more = len(rows) > safe_limit
        sliced = rows[:safe_limit]
        sliced.reverse()

        serialized = [
            cls.serialize_message(m, m.sender, fandom.owner_id) for m in sliced
        ]
        next_cursor = serialized[0].id if has_more and serialized else None

        return MessageListResponse(
            channel_id=channel.id,
            fandom_id=fandom.id,
            messages=serialized,
            has_more=has_more,
            next_cursor=next_cursor,
        )

    @classmethod
    async def send_message(
        cls,
        db: AsyncSession,
        channel_id: uuid.UUID,
        current_user: User,
        data: MessageCreate,
        perm_checker: IPermissionChecker,
    ) -> MessageOut:
        """Validates permissions, persists a new message, and broadcasts it over Socket.IO.

        Args:
            db: Active database session.
            channel_id: Target channel UUID.
            current_user: Authenticated sender.
            data: Message creation payload.
            perm_checker: Permission evaluation adapter.

        Returns:
            MessageOut: Persisted and broadcasted message DTO.
        """
        channel, fandom = await cls.resolve_channel_and_fandom(db, channel_id)
        if channel.type != "TEXT":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Chỉ có thể gửi tin nhắn văn bản vào kênh loại TEXT.",
            )

        eval_ctx = await perm_checker.verify(
            user_id=current_user.id,
            fandom_id=fandom.id,
            channel_id=channel.id,
            spec=SEND_MESSAGE_SPEC,
            error_detail="Bạn không có quyền gửi tin nhắn trong kênh này.",
        )

        if channel.is_announcement and not eval_ctx.has(Permission.SEND_ANNOUNCEMENT):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Chỉ Chủ Fandom hoặc Ban quản trị mới có quyền đăng thông báo trong kênh này.",
            )

        cleaned_content = data.content.strip()
        if not cleaned_content and not data.attachments:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Nội dung tin nhắn hoặc tệp đính kèm không được để trống.",
            )

        if data.attachments and not eval_ctx.has(Permission.ATTACH_FILES):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Bạn không có quyền đính kèm tệp hoặc hình ảnh trong kênh này.",
            )

        if _URL_PATTERN.search(cleaned_content) and not eval_ctx.has(Permission.EMBED_LINKS):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Bạn không có quyền chèn liên kết (link) trong kênh này.",
            )

        attachments_payload = [item.model_dump() for item in data.attachments]
        message = Message(
            channel_id=channel.id,
            sender_id=current_user.id,
            content=cleaned_content,
            attachments=attachments_payload if attachments_payload else None,
            reply_to_id=data.reply_to_id,
            reactions={},
        )
        db.add(message)
        await db.commit()
        await db.refresh(message)
        message.channel = channel

        message_out = cls.serialize_message(message, current_user, fandom.owner_id)

        from app.main import sio

        await sio.emit(
            "new_message",
            message_out.model_dump(mode="json"),
            room=f"channel:{channel.id}",
        )
        return message_out
