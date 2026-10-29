"""Shared Media Upload and Asset Management API Router.

Exposes endpoints for authenticated users to upload images and short videos
to Cloudinary and to remove unused assets owned by their account.
"""

import uuid
import redis.asyncio as aioredis
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status

from app.core.redis import get_redis
from app.modules.identity.models import User
from app.modules.identity.service import get_current_user
from app.modules.media.schemas import (
    MediaDeleteRequest,
    MediaDeleteResponse,
    MediaTarget,
    MediaUploadResponse,
)
from app.modules.media.service import MediaService

media_router = APIRouter(prefix="/api/v1/media", tags=["Media"])


@media_router.post(
    "/upload",
    response_model=MediaUploadResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Tải tệp phương tiện (Ảnh / Short Video) lên Cloudinary",
    description="""
    API dùng chung cho toàn hệ thống để tải ảnh đại diện, ảnh bìa, ảnh minh họa và video ngắn lên Cloudinary CDN:
    - **Kiểm tra chữ ký nhị phân (Magic Bytes)**: Chỉ chấp nhận ảnh (`JPG`, `PNG`, `WEBP`) và video ngắn (`MP4`, `WEBM`).
    - **Giới hạn dung lượng**:
      - `USER_AVATAR`, `FANDOM_AVATAR`: Tối đa **2 MB** (chỉ nhận ảnh).
      - `USER_BANNER`, `FANDOM_BANNER`: Tối đa **5 MB** (chỉ nhận ảnh).
      - `FANDOM_ILLUSTRATION`, `CHAT_ATTACHMENT`: Ảnh tối đa **5 MB**, Short Video tối đa **15 MB** (≤ 60 giây).
    - **Tự động ghi đè chống rác lưu trữ**: Với Avatar và Banner, hệ thống cố định `public_id` kèm `overwrite=True` để tự động xóa file cũ ngay khi tải file mới.
    - **Chống spam**: Giới hạn tối đa 10 lượt tải lên mỗi phút trên mỗi tài khoản.
    """,
    responses={
        400: {"description": "Định dạng tệp không hợp lệ hoặc thời lượng video vượt quá 60 giây"},
        401: {"description": "Chưa xác thực phiên đăng nhập"},
        413: {"description": "Dung lượng tệp vượt quá hạn mức cho phép"},
        429: {"description": "Vượt quá giới hạn tần suất tải tệp (10 tệp/phút)"},
    },
)
async def upload_media(
    file: UploadFile = File(..., description="Tệp hình ảnh hoặc video ngắn cần tải lên"),
    target: MediaTarget = Form(
        default=MediaTarget.USER_AVATAR,
        description="Mục đích sử dụng tệp: USER_AVATAR, USER_BANNER, FANDOM_AVATAR, FANDOM_BANNER, FANDOM_ILLUSTRATION, CHAT_ATTACHMENT",
    ),
    entity_id: uuid.UUID | None = Form(
        default=None,
        description="ID của Fandom hoặc Kênh (tùy chọn, dùng khi cập nhật media của Fandom/Kênh cụ thể)",
    ),
    current_user: User = Depends(get_current_user),
    redis: aioredis.Redis = Depends(get_redis),
):
    """Validates and uploads a media file to Cloudinary, returning its public CDN URL."""
    return await MediaService.upload_file(
        file=file,
        user_id=current_user.id,
        target=target,
        redis=redis,
        entity_id=entity_id,
    )


@media_router.delete(
    "",
    response_model=MediaDeleteResponse,
    summary="Xóa tệp phương tiện trên Cloudinary theo URL",
    description="Xóa tệp ảnh hoặc video ngắn đã tải lên khỏi kho lưu trữ Cloudinary.",
    responses={
        400: {"description": "URL không hợp lệ"},
        401: {"description": "Chưa xác thực phiên đăng nhập"},
        403: {"description": "Không có quyền xóa tệp của người dùng khác"},
    },
)
async def delete_media(
    data: MediaDeleteRequest,
    current_user: User = Depends(get_current_user),
):
    """Deletes a Cloudinary media asset by its delivery URL."""
    info = MediaService.extract_cloudinary_asset_info(data.url)
    if not info:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="URL không thuộc kho lưu trữ Cloudinary hợp lệ của hệ thống.",
        )

    public_id, _ = info
    user_prefix = f"fanspace/users/{current_user.id}/"
    if public_id.startswith("fanspace/users/") and not public_id.startswith(user_prefix):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Bạn không có quyền xóa tệp phương tiện thuộc về tài khoản khác.",
        )

    return await MediaService.delete_by_url(data.url)
