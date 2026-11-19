"""API Routers for fandom communication channels and real-time messages."""

import uuid
import redis.asyncio as aioredis
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.permissions import IPermissionChecker, get_permission_checker
from app.core.redis import get_redis
from app.modules.chat.schemas import (
    ChannelCreate,
    ChannelDeleteResponse,
    ChannelOut,
    ChannelUpdate,
    FandomChannelsListResponse,
    MessageCreate,
    MessageListResponse,
    MessageOut,
    MessageReactionRequest,
    MessageUpdate,
    VoiceRaiseHandRequest,
    VoiceRoomStateOut,
    VoiceSelfMuteRequest,
    VoiceSpeakerManageRequest,
    VoiceTokenOut,
)
from app.modules.chat.service import ChannelService, MessageService
from app.modules.chat.voice_service import VoiceChannelService
from app.modules.identity.models import User
from app.modules.identity.service import get_current_user

chat_router = APIRouter(prefix="/api/v1/fandoms", tags=["Channels & Chat"])
messages_router = APIRouter(prefix="/api/v1/channels", tags=["Channels & Chat"])


@chat_router.get(
    "/{fandom_identifier}/channels",
    response_model=FandomChannelsListResponse,
    summary="Lấy danh sách kênh giao tiếp trong Fandom",
    description="""
    Trả về danh sách các kênh văn bản (Text), kênh thông báo (Announcement) và kênh thoại (Voice)
    mà thành viên hiện tại có quyền xem, kèm theo mảng quyền hiệu lực `my_permissions` trên từng kênh.
    """,
)
async def list_fandom_channels(
    fandom_identifier: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    perm_checker: IPermissionChecker = Depends(get_permission_checker),
) -> FandomChannelsListResponse:
    """Lists all accessible communication channels in a fandom workspace."""
    return await ChannelService.list_channels(
        db=db,
        fandom_identifier=fandom_identifier,
        current_user=current_user,
        perm_checker=perm_checker,
    )


@chat_router.post(
    "/{fandom_identifier}/channels",
    response_model=ChannelOut,
    status_code=status.HTTP_201_CREATED,
    summary="Tạo kênh giao tiếp mới trong Fandom",
    description="Tạo kênh văn bản hoặc kênh thoại mới (yêu cầu quyền `MANAGE_CHANNELS`).",
)
async def create_fandom_channel(
    fandom_identifier: str,
    data: ChannelCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    perm_checker: IPermissionChecker = Depends(get_permission_checker),
) -> ChannelOut:
    """Creates a new communication channel in a fandom workspace."""
    return await ChannelService.create_channel(
        db=db,
        fandom_identifier=fandom_identifier,
        current_user=current_user,
        data=data,
        perm_checker=perm_checker,
    )


@chat_router.put(
    "/{fandom_identifier}/channels/{channel_id}",
    response_model=ChannelOut,
    summary="Cập nhật cấu hình kênh giao tiếp",
    description="Chỉnh sửa tên kênh, chủ đề, chế độ thông báo hoặc thời gian hồi Slow-mode (yêu cầu quyền `MANAGE_CHANNELS`).",
)
async def update_fandom_channel(
    fandom_identifier: str,
    channel_id: uuid.UUID,
    data: ChannelUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    perm_checker: IPermissionChecker = Depends(get_permission_checker),
) -> ChannelOut:
    """Updates an existing communication channel in a fandom workspace."""
    return await ChannelService.update_channel(
        db=db,
        fandom_identifier=fandom_identifier,
        channel_id=channel_id,
        current_user=current_user,
        data=data,
        perm_checker=perm_checker,
    )


@chat_router.delete(
    "/{fandom_identifier}/channels/{channel_id}",
    response_model=ChannelDeleteResponse,
    summary="Xóa kênh giao tiếp khỏi Fandom",
    description="Xóa kênh khỏi Fandom (yêu cầu quyền `MANAGE_CHANNELS`, không cho phép xóa kênh duy nhất còn lại).",
)
async def delete_fandom_channel(
    fandom_identifier: str,
    channel_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    perm_checker: IPermissionChecker = Depends(get_permission_checker),
) -> ChannelDeleteResponse:
    """Deletes a communication channel from a fandom workspace."""
    return await ChannelService.delete_channel(
        db=db,
        fandom_identifier=fandom_identifier,
        channel_id=channel_id,
        current_user=current_user,
        perm_checker=perm_checker,
    )


@messages_router.get(
    "/{channel_id}/messages",
    response_model=MessageListResponse,
    summary="Lấy lịch sử tin nhắn trong kênh (Keyset Cursor Pagination)",
    description="Trả về danh sách tin nhắn theo thứ tự thời gian kèm con trỏ `next_cursor` để tải tin nhắn cũ hơn.",
)
async def list_channel_messages(
    channel_id: uuid.UUID,
    before_id: uuid.UUID | None = Query(
        default=None,
        description="Con trỏ ID tin nhắn để tải các tin nhắn cũ hơn trước đó",
    ),
    limit: int = Query(
        default=30,
        ge=1,
        le=100,
        description="Số lượng tin nhắn tối đa mỗi lần tải (1 - 100)",
    ),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    perm_checker: IPermissionChecker = Depends(get_permission_checker),
) -> MessageListResponse:
    """Retrieves paginated message history for a channel."""
    return await MessageService.list_messages(
        db=db,
        channel_id=channel_id,
        current_user=current_user,
        perm_checker=perm_checker,
        before_id=before_id,
        limit=limit,
    )


@messages_router.get(
    "/{channel_id}/pins",
    response_model=list[MessageOut],
    summary="Lấy danh sách các tin nhắn đang được ghim trong kênh",
    description="Trả về danh sách các tin nhắn đã được ghim bởi Ban quản trị trong kênh.",
)
async def list_pinned_channel_messages(
    channel_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    perm_checker: IPermissionChecker = Depends(get_permission_checker),
) -> list[MessageOut]:
    """Lists all currently pinned messages in a channel."""
    return await MessageService.list_pinned_messages(
        db=db,
        channel_id=channel_id,
        current_user=current_user,
        perm_checker=perm_checker,
    )


@messages_router.post(
    "/{channel_id}/messages",
    response_model=MessageOut,
    status_code=status.HTTP_201_CREATED,
    summary="Gửi tin nhắn mới vào kênh",
    description="Kiểm tra quyền gửi tin nhắn/thông báo/đính kèm và Slow-mode, lưu CSDL và phát sóng thời gian thực qua Socket.IO.",
)
async def send_channel_message(
    channel_id: uuid.UUID,
    data: MessageCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    perm_checker: IPermissionChecker = Depends(get_permission_checker),
    redis: aioredis.Redis = Depends(get_redis),
) -> MessageOut:
    """Sends a new message into a text or announcement channel."""
    return await MessageService.send_message(
        db=db,
        channel_id=channel_id,
        current_user=current_user,
        data=data,
        perm_checker=perm_checker,
        redis=redis,
    )


@messages_router.put(
    "/{channel_id}/messages/{message_id}",
    response_model=MessageOut,
    summary="Chỉnh sửa nội dung tin nhắn",
    description="Cho phép tác giả của tin nhắn chỉnh sửa nội dung văn bản (gắn nhãn `đã chỉnh sửa`).",
)
async def edit_channel_message(
    channel_id: uuid.UUID,
    message_id: uuid.UUID,
    data: MessageUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    perm_checker: IPermissionChecker = Depends(get_permission_checker),
) -> MessageOut:
    """Edits the text content of an existing message."""
    return await MessageService.edit_message(
        db=db,
        channel_id=channel_id,
        message_id=message_id,
        current_user=current_user,
        data=data,
        perm_checker=perm_checker,
    )


@messages_router.delete(
    "/{channel_id}/messages/{message_id}",
    response_model=MessageOut,
    summary="Thu hồi hoặc xóa kiểm duyệt tin nhắn",
    description="Cho phép tác giả tự thu hồi tin nhắn của mình hoặc người có quyền `MODERATE_CHAT` xóa kiểm duyệt tin nhắn vi phạm.",
)
async def recall_channel_message(
    channel_id: uuid.UUID,
    message_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    perm_checker: IPermissionChecker = Depends(get_permission_checker),
) -> MessageOut:
    """Recalls or moderates a channel message."""
    return await MessageService.recall_message(
        db=db,
        channel_id=channel_id,
        message_id=message_id,
        current_user=current_user,
        perm_checker=perm_checker,
    )


@messages_router.post(
    "/{channel_id}/messages/{message_id}/reactions",
    response_model=MessageOut,
    summary="Thả hoặc gỡ biểu tượng cảm xúc (Emoji Reaction) trên tin nhắn",
    description="Bật/tắt biểu tượng cảm xúc của người dùng hiện tại trên tin nhắn.",
)
async def toggle_message_reaction(
    channel_id: uuid.UUID,
    message_id: uuid.UUID,
    data: MessageReactionRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    perm_checker: IPermissionChecker = Depends(get_permission_checker),
) -> MessageOut:
    """Toggles an emoji reaction on a channel message."""
    return await MessageService.toggle_reaction(
        db=db,
        channel_id=channel_id,
        message_id=message_id,
        current_user=current_user,
        data=data,
        perm_checker=perm_checker,
    )


@messages_router.post(
    "/{channel_id}/messages/{message_id}/pin",
    response_model=MessageOut,
    summary="Ghim hoặc bỏ ghim tin nhắn trong kênh",
    description="Ghim hoặc bỏ ghim tin nhắn quan trọng lên đầu kênh (yêu cầu quyền `MODERATE_CHAT`).",
)
async def toggle_pin_channel_message(
    channel_id: uuid.UUID,
    message_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    perm_checker: IPermissionChecker = Depends(get_permission_checker),
) -> MessageOut:
    """Pins or unpins a message in a channel."""
    return await MessageService.toggle_pin_message(
        db=db,
        channel_id=channel_id,
        message_id=message_id,
        current_user=current_user,
        perm_checker=perm_checker,
    )


# ---------------------------------------------------------------------------
# FR-11 (UC-06): Real-time Voice Channel via Agora RTC
# ---------------------------------------------------------------------------


@messages_router.post(
    "/{channel_id}/voice/token",
    response_model=VoiceTokenOut,
    summary="Cấp Dynamic Agora RTC Token và tham gia phòng thoại",
    description="Kiểm tra quyền `VOICE_CONNECT` và giới hạn `max_members`, ghi nhận người dùng vào phòng thoại trên Redis và trả về Dynamic Agora RTC Token.",
)
async def issue_voice_channel_token(
    channel_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    perm_checker: IPermissionChecker = Depends(get_permission_checker),
    redis: aioredis.Redis = Depends(get_redis),
) -> VoiceTokenOut:
    """Issues a dynamic Agora RTC token and joins the caller to the voice room."""
    return await VoiceChannelService.issue_voice_token_and_join(
        db=db,
        channel_id=channel_id,
        current_user=current_user,
        perm_checker=perm_checker,
        redis=redis,
    )


@messages_router.get(
    "/{channel_id}/voice/state",
    response_model=VoiceRoomStateOut,
    summary="Xem trạng thái phòng thoại thời gian thực",
    description="Trả về danh sách người phát biểu (Speakers), thính giả (Listeners) và danh sách giơ tay xin nói.",
)
async def get_voice_channel_state(
    channel_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    perm_checker: IPermissionChecker = Depends(get_permission_checker),
    redis: aioredis.Redis = Depends(get_redis),
) -> VoiceRoomStateOut:
    """Retrieves the real-time state of a voice channel room."""
    return await VoiceChannelService.get_voice_room_state(
        db=db,
        channel_id=channel_id,
        current_user=current_user,
        perm_checker=perm_checker,
        redis=redis,
    )


@messages_router.post(
    "/{channel_id}/voice/raise-hand",
    response_model=VoiceRoomStateOut,
    summary="Giơ tay hoặc hạ tay xin phát biểu trong phòng Stage Room",
    description="Cho phép Thính giả trong kênh thoại `STAGE_ROOM` giơ tay xin lên sân khấu phát biểu.",
)
async def toggle_voice_raise_hand(
    channel_id: uuid.UUID,
    data: VoiceRaiseHandRequest = VoiceRaiseHandRequest(),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    perm_checker: IPermissionChecker = Depends(get_permission_checker),
    redis: aioredis.Redis = Depends(get_redis),
) -> VoiceRoomStateOut:
    """Toggles the raise-hand flag for a participant in a Stage Room."""
    return await VoiceChannelService.toggle_raise_hand(
        db=db,
        channel_id=channel_id,
        current_user=current_user,
        data=data,
        perm_checker=perm_checker,
        redis=redis,
    )


@messages_router.put(
    "/{channel_id}/voice/speakers/{user_id}",
    response_model=VoiceRoomStateOut,
    summary="Điều phối người phát biểu hoặc tắt mic thành viên (Owner/Mod)",
    description="Cho phép Chủ Fandom hoặc Điều hành viên mời thính giả lên làm Speaker, đưa xuống Listener hoặc tắt mic.",
)
async def manage_voice_channel_speaker(
    channel_id: uuid.UUID,
    user_id: uuid.UUID,
    data: VoiceSpeakerManageRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    perm_checker: IPermissionChecker = Depends(get_permission_checker),
    redis: aioredis.Redis = Depends(get_redis),
) -> VoiceRoomStateOut:
    """Promotes, demotes, or mutes a participant in a voice channel."""
    return await VoiceChannelService.manage_speaker(
        db=db,
        channel_id=channel_id,
        target_user_id=user_id,
        current_user=current_user,
        data=data,
        perm_checker=perm_checker,
        redis=redis,
    )


@messages_router.put(
    "/{channel_id}/voice/me/mute",
    response_model=VoiceRoomStateOut,
    summary="Bật hoặc tắt mic cá nhân trong phòng thoại",
    description="Cho phép người dùng có vai trò `SPEAKER` tự bật/tắt mic của chính mình.",
)
async def toggle_voice_self_mute(
    channel_id: uuid.UUID,
    data: VoiceSelfMuteRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    perm_checker: IPermissionChecker = Depends(get_permission_checker),
    redis: aioredis.Redis = Depends(get_redis),
) -> VoiceRoomStateOut:
    """Toggles the caller's own microphone state in a voice channel."""
    return await VoiceChannelService.toggle_self_mute(
        db=db,
        channel_id=channel_id,
        current_user=current_user,
        data=data,
        perm_checker=perm_checker,
        redis=redis,
    )


@messages_router.post(
    "/{channel_id}/voice/mute-all",
    response_model=VoiceRoomStateOut,
    summary="Ngắt mic toàn bộ thành viên trong phòng thoại (Owner/Mod)",
    description="Tắt mic tất cả người tham gia khác trong phòng thoại (yêu cầu quyền `MODERATE_CHAT` hoặc `MANAGE_CHANNELS`).",
)
async def mute_all_voice_channel(
    channel_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    perm_checker: IPermissionChecker = Depends(get_permission_checker),
    redis: aioredis.Redis = Depends(get_redis),
) -> VoiceRoomStateOut:
    """Mutes all non-caller participants in the voice room."""
    return await VoiceChannelService.mute_all_participants(
        db=db,
        channel_id=channel_id,
        current_user=current_user,
        perm_checker=perm_checker,
        redis=redis,
    )


@messages_router.post(
    "/{channel_id}/voice/leave",
    response_model=VoiceRoomStateOut,
    summary="Rời khỏi phòng thoại",
    description="Gỡ người dùng khỏi danh sách đang kết nối trong phòng thoại và giải phóng slot `max_members`.",
)
async def leave_voice_channel_room(
    channel_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    perm_checker: IPermissionChecker = Depends(get_permission_checker),
    redis: aioredis.Redis = Depends(get_redis),
) -> VoiceRoomStateOut:
    """Disconnects the caller from a voice channel room."""
    return await VoiceChannelService.leave_voice_room(
        db=db,
        channel_id=channel_id,
        current_user=current_user,
        perm_checker=perm_checker,
        redis=redis,
    )

