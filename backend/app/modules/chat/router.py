"""API Routers for fandom communication channels and real-time messages."""

import uuid
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.permissions import IPermissionChecker, get_permission_checker
from app.modules.chat.schemas import (
    ChannelCreate,
    ChannelDeleteResponse,
    ChannelOut,
    ChannelUpdate,
    FandomChannelsListResponse,
    MessageCreate,
    MessageListResponse,
    MessageOut,
)
from app.modules.chat.service import ChannelService, MessageService
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


@messages_router.post(
    "/{channel_id}/messages",
    response_model=MessageOut,
    status_code=status.HTTP_201_CREATED,
    summary="Gửi tin nhắn mới vào kênh",
    description="Kiểm tra quyền gửi tin nhắn/thông báo/đính kèm, lưu CSDL và phát sóng thời gian thực qua Socket.IO.",
)
async def send_channel_message(
    channel_id: uuid.UUID,
    data: MessageCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    perm_checker: IPermissionChecker = Depends(get_permission_checker),
) -> MessageOut:
    """Sends a new message into a text or announcement channel."""
    return await MessageService.send_message(
        db=db,
        channel_id=channel_id,
        current_user=current_user,
        data=data,
        perm_checker=perm_checker,
    )
