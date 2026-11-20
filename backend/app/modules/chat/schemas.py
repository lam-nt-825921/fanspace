"""Pydantic request and response schemas for fandom communication channels and messages."""

import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator


ChannelType = Literal["TEXT", "VOICE"]
VoiceRoomType = Literal["OPEN_MIC", "STAGE_ROOM"]


class ChannelCreate(BaseModel):
    """Payload for creating a new communication channel inside a fandom."""

    name: str = Field(
        ...,
        min_length=2,
        max_length=50,
        description="Tên hiển thị của kênh (từ 2 đến 50 ký tự)",
    )
    type: ChannelType = Field(
        default="TEXT",
        description="Loại kênh: TEXT (Văn bản) hoặc VOICE (Kênh thoại)",
    )
    topic: str | None = Field(
        default=None,
        max_length=255,
        description="Chủ đề hoặc mô tả ngắn của kênh",
    )
    is_announcement: bool = Field(
        default=False,
        description="Kênh thông báo một chiều (chỉ Ban quản trị được gửi tin)",
    )
    is_membership_only: bool = Field(
        default=False,
        description="Kênh giới hạn dành riêng cho thành viên có gói hội viên",
    )
    min_membership_tier_level: int = Field(
        default=0,
        ge=0,
        le=4,
        description="Cấp độ gói Hội viên tối thiểu (0 = mọi gói Hội viên, 1..4 = từ Tier N trở lên)",
    )
    membership_bypass_slowmode: bool = Field(
        default=False,
        description="Cho phép Hội viên có đặc quyền Kênh ưu tiên được miễn Slow-mode trong kênh này",
    )
    required_role_id: uuid.UUID | None = Field(
        default=None,
        description="Mã định danh vai trò cụ thể yêu cầu để truy cập kênh",
    )
    allowed_role_ids: list[uuid.UUID] | None = Field(
        default=None,
        description="Danh sách các Vai trò nội bộ được phép truy cập kênh (hỗ trợ chọn nhiều Role)",
    )
    max_members: int = Field(
        default=0,
        ge=0,
        le=100000,
        description="Giới hạn số người tham gia đồng thời trong kênh (0 = Không giới hạn)",
    )
    role_permissions_bitmask: int = Field(
        default=32831,
        ge=0,
        description="Bitmask quyền chi tiết cấp cho nhóm Vai trò nội bộ trên kênh này",
    )
    membership_permissions_bitmask: int = Field(
        default=32831,
        ge=0,
        description="Bitmask quyền chi tiết cấp cho nhóm Hội viên VIP trên kênh này",
    )
    slow_mode_seconds: int = Field(
        default=0,
        ge=0,
        le=21600,
        description="Thời gian chờ giữa hai tin nhắn liên tiếp (giây)",
    )
    voice_room_type: VoiceRoomType | None = Field(
        default=None,
        description="Chế độ phòng thoại: OPEN_MIC hoặc STAGE_ROOM",
    )

    @field_validator("name")
    @classmethod
    def validate_channel_name(cls, value: str) -> str:
        """Trims and validates the channel name."""
        cleaned = value.strip()
        if len(cleaned) < 2:
            raise ValueError("Tên kênh phải có ít nhất 2 ký tự.")
        return cleaned


class ChannelUpdate(BaseModel):
    """Payload for updating an existing communication channel."""

    name: str | None = Field(
        default=None,
        min_length=2,
        max_length=50,
        description="Tên hiển thị mới của kênh",
    )
    topic: str | None = Field(
        default=None,
        max_length=255,
        description="Chủ đề mới của kênh",
    )
    position: int | None = Field(
        default=None,
        ge=0,
        description="Vị trí sắp xếp hiển thị của kênh",
    )
    is_announcement: bool | None = Field(
        default=None,
        description="Cập nhật chế độ kênh thông báo",
    )
    is_membership_only: bool | None = Field(
        default=None,
        description="Cập nhật chế độ giới hạn hội viên",
    )
    min_membership_tier_level: int | None = Field(
        default=None,
        ge=0,
        le=4,
        description="Cấp độ gói Hội viên tối thiểu (0..4)",
    )
    membership_bypass_slowmode: bool | None = Field(
        default=None,
        description="Cho phép Hội viên miễn Slow-mode trong kênh",
    )
    required_role_id: uuid.UUID | None = Field(
        default=None,
        description="Vai trò yêu cầu mới",
    )
    allowed_role_ids: list[uuid.UUID] | None = Field(
        default=None,
        description="Danh sách các Vai trò nội bộ được phép truy cập kênh",
    )
    max_members: int | None = Field(
        default=None,
        ge=0,
        le=100000,
        description="Giới hạn số người tham gia đồng thời trong kênh (0 = Không giới hạn)",
    )
    role_permissions_bitmask: int | None = Field(
        default=None,
        ge=0,
        description="Bitmask quyền chi tiết cấp cho nhóm Vai trò nội bộ trên kênh",
    )
    membership_permissions_bitmask: int | None = Field(
        default=None,
        ge=0,
        description="Bitmask quyền chi tiết cấp cho nhóm Hội viên VIP trên kênh",
    )
    slow_mode_seconds: int | None = Field(
        default=None,
        ge=0,
        le=21600,
        description="Thời gian chờ Slow-mode mới (giây)",
    )
    voice_room_type: VoiceRoomType | None = Field(
        default=None,
        description="Chế độ phòng thoại mới",
    )


class ChannelOut(BaseModel):
    """Serialized representation of a fandom channel with caller's effective permissions."""

    id: uuid.UUID
    fandom_id: uuid.UUID
    name: str
    type: str
    topic: str | None = None
    position: int
    is_announcement: bool
    is_membership_only: bool
    min_membership_tier_level: int = 0
    membership_bypass_slowmode: bool = False
    required_role_id: uuid.UUID | None = None
    allowed_role_ids: list[uuid.UUID] = Field(
        default_factory=list,
        description="Danh sách các Vai trò nội bộ được phép truy cập kênh",
    )
    max_members: int = 0
    role_permissions_bitmask: int = 32831
    membership_permissions_bitmask: int = 32831
    slow_mode_seconds: int
    voice_room_type: str | None = None
    created_at: datetime
    my_permissions: list[str] = Field(
        default_factory=list,
        description="Danh sách các quyền hiệu lực của người dùng hiện tại trên kênh này",
    )

    model_config = ConfigDict(from_attributes=True)


class FandomChannelsListResponse(BaseModel):
    """Response payload listing all accessible channels in a fandom workspace."""

    fandom_id: uuid.UUID
    slug: str
    my_fandom_permissions: list[str] = Field(
        default_factory=list,
        description="Danh sách quyền hiệu lực cấp Fandom của người dùng hiện tại",
    )
    channels: list[ChannelOut]


class ChannelDeleteResponse(BaseModel):
    """Response payload confirming channel deletion."""

    success: bool
    message: str
    deleted_channel_id: uuid.UUID


class MessageAttachmentItem(BaseModel):
    """Metadata for a single media attachment inside a chat message."""

    url: str = Field(..., min_length=5, max_length=2048, description="Đường dẫn tệp phương tiện")
    type: str = Field(default="IMAGE", max_length=30, description="Loại tệp đính kèm (IMAGE, VIDEO, FILE)")
    filename: str | None = Field(default=None, max_length=255, description="Tên tệp hiển thị")


class MessageSenderOut(BaseModel):
    """Public profile summary of the user who sent a message."""

    id: uuid.UUID
    username: str
    display_name: str
    avatar_url: str | None = None
    is_owner: bool = False


class MessageReplyPreviewOut(BaseModel):
    """Compact preview of the parent message being replied to."""

    id: uuid.UUID
    sender_id: uuid.UUID
    sender_display_name: str
    content: str
    is_recalled: bool = False


class MessageCreate(BaseModel):
    """Payload for sending a new message into a text or announcement channel."""

    content: str = Field(
        default="",
        max_length=4000,
        description="Nội dung văn bản của tin nhắn",
    )
    attachments: list[MessageAttachmentItem] = Field(
        default_factory=list,
        max_length=5,
        description="Danh sách tệp đính kèm (tối đa 5 tệp)",
    )
    reply_to_id: uuid.UUID | None = Field(
        default=None,
        description="Mã định danh tin nhắn gốc được trả lời",
    )


class MessageUpdate(BaseModel):
    """Payload for editing the text content of an existing message."""

    content: str = Field(
        ...,
        min_length=1,
        max_length=4000,
        description="Nội dung mới của tin nhắn sau khi chỉnh sửa",
    )


class MessageReactionRequest(BaseModel):
    """Payload for toggling an emoji reaction on a message."""

    emoji: str = Field(
        ...,
        min_length=1,
        max_length=32,
        description="Biểu tượng cảm xúc (Emoji) muốn thả hoặc gỡ",
    )


class MessageOut(BaseModel):
    """Serialized representation of a channel message."""

    id: uuid.UUID
    channel_id: uuid.UUID
    fandom_id: uuid.UUID
    sender_id: uuid.UUID
    sender: MessageSenderOut
    content: str
    attachments: list[dict] = Field(default_factory=list)
    reply_to_id: uuid.UUID | None = None
    reply_to: MessageReplyPreviewOut | None = None
    is_pinned: bool = False
    reactions: dict = Field(default_factory=dict)
    is_edited: bool = False
    is_recalled: bool = False
    created_at: datetime
    updated_at: datetime


class MessageListResponse(BaseModel):
    """Paginated response containing chronological messages for a channel."""

    channel_id: uuid.UUID
    fandom_id: uuid.UUID
    messages: list[MessageOut]
    has_more: bool
    next_cursor: uuid.UUID | None = None


VoiceParticipantRole = Literal["SPEAKER", "LISTENER"]


class VoiceParticipantOut(BaseModel):
    """Real-time state of a member connected to a voice room."""

    user_id: uuid.UUID
    agora_uid: int | None = None
    username: str
    display_name: str
    avatar_url: str | None = None
    role: VoiceParticipantRole = "LISTENER"
    is_muted: bool = True
    is_hand_raised: bool = False
    is_owner: bool = False
    joined_at: datetime


class VoiceRoomStateOut(BaseModel):
    """Snapshot of a voice channel room's speakers, listeners, and raise-hand queue."""

    channel_id: uuid.UUID
    fandom_id: uuid.UUID
    channel_name: str
    voice_room_type: str = "OPEN_MIC"
    max_members: int = 0
    active_count: int = 0
    participants: list[VoiceParticipantOut] = Field(default_factory=list)
    raised_hand_user_ids: list[str] = Field(default_factory=list)


class VoiceTokenOut(BaseModel):
    """Dynamic Agora RTC Token bundle and room snapshot returned upon joining a voice channel."""

    app_id: str
    channel_name: str
    rtc_token: str
    uid: int
    role: VoiceParticipantRole
    can_publish: bool
    expires_in: int
    room_state: VoiceRoomStateOut


class VoiceRaiseHandRequest(BaseModel):
    """Payload for toggling raise-hand status in a Stage Room voice channel."""

    raised: bool = Field(
        default=True,
        description="True để giơ tay xin phát biểu, False để hạ tay",
    )


class VoiceSpeakerManageRequest(BaseModel):
    """Payload for a moderator/owner to promote, demote, or mute a participant in a voice room."""

    role: VoiceParticipantRole | None = Field(
        default=None,
        description="Cập nhật vai trò trong phòng thoại: SPEAKER hoặc LISTENER",
    )
    is_muted: bool | None = Field(
        default=None,
        description="Trạng thái tắt mic bắt buộc (True = Tắt mic, False = Cho phép mở mic)",
    )


class VoiceSelfMuteRequest(BaseModel):
    """Payload for a voice participant to toggle their own microphone state."""

    is_muted: bool = Field(
        ...,
        description="True để tắt mic cá nhân, False để bật mic phát biểu",
    )

