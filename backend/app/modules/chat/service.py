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
