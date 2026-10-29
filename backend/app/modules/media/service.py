"""Shared Media Upload, Validation, and Cloudinary Asset Lifecycle Service.

Provides:
- Magic-byte file signature inspection (JPEG, PNG, WEBP, MP4, WEBM) to prevent MIME spoofing.
- Target-specific size quotas (2 MB for avatars, 5 MB for banners/images, 15 MB for short videos).
- Per-user Redis upload rate limiting (10 uploads/minute).
- Deterministic `public_id` overwrite (`overwrite=True, invalidate=True`) for single-value assets
  (`USER_AVATAR`, `USER_BANNER`, `FANDOM_AVATAR`, `FANDOM_BANNER`) so old files never accumulate.
- Asynchronous background cleanup (`delete_by_url`, `cleanup_replaced_urls`) for multi-file
  collections (`illustration_urls`) and entity deletion.
"""

import asyncio
import io
import re
import uuid
import cloudinary
import cloudinary.api
import cloudinary.uploader
import redis.asyncio as aioredis
from fastapi import HTTPException, UploadFile, status

from app.core.config import get_settings
from app.modules.media.schemas import (
    MediaDeleteResponse,
    MediaResourceType,
    MediaTarget,
    MediaUploadResponse,
)

settings = get_settings()

# Regex extracting (resource_type, public_id) from a Cloudinary delivery URL:
# https://res.cloudinary.com/<cloud_name>/<resource_type>/upload/(?:v1234567/)?<public_id>.<ext>
_CLOUDINARY_URL_PATTERN = re.compile(
    r"^https?://res\.cloudinary\.com/(?P<cloud_name>[^/]+)/(?P<resource_type>image|video)/upload/"
    r"(?:[^/]+/)*?(?:v\d+/)?(?P<public_id>fanspace/[^.?#]+)\.[a-zA-Z0-9]+$"
)

IMAGE_TARGETS = {
    MediaTarget.USER_AVATAR,
    MediaTarget.USER_BANNER,
    MediaTarget.FANDOM_AVATAR,
    MediaTarget.FANDOM_BANNER,
}

HYBRID_TARGETS = {
    MediaTarget.FANDOM_ILLUSTRATION,
    MediaTarget.CHAT_ATTACHMENT,
}


class MediaService:
    """Centralized media upload and lifecycle management service backed by Cloudinary."""

    @staticmethod
    def configure_cloudinary() -> None:
        """Initializes the Cloudinary SDK with credentials from application settings.

        Raises:
            HTTPException: 500 Internal Server Error if Cloudinary credentials are missing.
        """
        if (
            not settings.CLOUDINARY_CLOUD_NAME
            or not settings.CLOUDINARY_API_KEY
            or not settings.CLOUDINARY_API_SECRET
        ):
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Hệ thống chưa cấu hình thông tin kết nối Cloudinary (CLOUDINARY_CLOUD_NAME, API_KEY, API_SECRET).",
            )
        cloudinary.config(
            cloud_name=settings.CLOUDINARY_CLOUD_NAME,
            api_key=settings.CLOUDINARY_API_KEY,
            api_secret=settings.CLOUDINARY_API_SECRET,
            secure=True,
        )

    @classmethod
    async def ping_cloudinary(cls) -> bool:
        """Verifies live connectivity and credentials against the Cloudinary API.

        Returns:
            bool: True if Cloudinary responds with status 'ok'.
        """
        cls.configure_cloudinary()
        res = await asyncio.to_thread(cloudinary.api.ping)
        return res.get("status") == "ok"

    @staticmethod
    def detect_media_signature(header: bytes) -> tuple[MediaResourceType, str]:
        """Inspects file magic bytes to determine authentic media type and format.

        Args:
            header (bytes): First 16+ bytes of the uploaded file.

        Returns:
            tuple[MediaResourceType, str]: Detected resource type ('image' or 'video') and format extension.

        Raises:
            HTTPException: 400 Bad Request if the file header does not match any supported signature.
        """
        if len(header) < 12:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Tệp tải lên rỗng hoặc bị hỏng.",
            )

        # Image signatures
        if header.startswith(b"\xff\xd8\xff"):
            return MediaResourceType.IMAGE, "jpg"
        if header.startswith(b"\x89PNG\r\n\x1a\n"):
            return MediaResourceType.IMAGE, "png"
        if header[:4] == b"RIFF" and header[8:12] == b"WEBP":
            return MediaResourceType.IMAGE, "webp"

        # Video signatures
        if header[4:8] == b"ftyp":
            return MediaResourceType.VIDEO, "mp4"
        if header.startswith(b"\x1a\x45\xdf\xa3"):
            return MediaResourceType.VIDEO, "webm"

        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Định dạng tệp không được hỗ trợ. Chỉ chấp nhận ảnh (JPG, PNG, WEBP) hoặc video ngắn (MP4, WEBM).",
        )

    @classmethod
    def validate_file_bytes(
        cls,
        content: bytes,
        target: MediaTarget,
    ) -> tuple[MediaResourceType, str]:
        """Validates file magic bytes and enforces size quotas for the given target context.

        Args:
            content (bytes): Raw binary content of the uploaded file.
            target (MediaTarget): Intended usage context of the media file.

        Returns:
            tuple[MediaResourceType, str]: Validated resource type and file extension.

        Raises:
            HTTPException: 400 if format is disallowed for the target, or 413 if file size exceeds quota.
        """
        if not content:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Tệp tải lên không được để trống.",
            )

        resource_type, ext = cls.detect_media_signature(content[:16])
        size_bytes = len(content)

        if target in IMAGE_TARGETS and resource_type != MediaResourceType.IMAGE:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Mục này chỉ chấp nhận tệp hình ảnh (JPG, PNG, WEBP), không chấp nhận video.",
            )

        # Enforce size quota per target and resource type
        if target in (MediaTarget.USER_AVATAR, MediaTarget.FANDOM_AVATAR):
            max_bytes = settings.MEDIA_MAX_AVATAR_BYTES
            max_label = f"{max_bytes // (1024 * 1024)} MB"
        elif target in (MediaTarget.USER_BANNER, MediaTarget.FANDOM_BANNER):
            max_bytes = settings.MEDIA_MAX_BANNER_BYTES
            max_label = f"{max_bytes // (1024 * 1024)} MB"
        elif resource_type == MediaResourceType.IMAGE:
            max_bytes = settings.MEDIA_MAX_IMAGE_BYTES
            max_label = f"{max_bytes // (1024 * 1024)} MB"
        else:
            max_bytes = settings.MEDIA_MAX_VIDEO_BYTES
            max_label = f"{max_bytes // (1024 * 1024)} MB"

        if size_bytes > max_bytes:
            raise HTTPException(
                status_code=status.HTTP_413_CONTENT_TOO_LARGE,
                detail=f"Dung lượng tệp vượt quá giới hạn cho phép (tối đa {max_label} cho {target.value}).",
            )

        return resource_type, ext

    @staticmethod
    async def check_upload_rate_limit(redis: aioredis.Redis, user_id: uuid.UUID) -> None:
        """Enforces per-user upload rate limits using a Redis counter with sliding TTL.

        Args:
            redis (aioredis.Redis): Active Redis client.
            user_id (uuid.UUID): Authenticated uploader's user ID.

        Raises:
            HTTPException: 429 Too Many Requests if the user exceeds the per-minute upload quota.
        """
        key = f"ratelimit:media:upload:{user_id}"
        count = await redis.incr(key)
        if count == 1:
            await redis.expire(key, settings.MEDIA_UPLOAD_RATE_LIMIT_WINDOW)
        if count > settings.MEDIA_UPLOAD_RATE_LIMIT_MAX:
            ttl = await redis.ttl(key)
            wait_sec = max(ttl, 1)
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=f"Bạn đã tải lên quá nhiều tệp liên tiếp. Vui lòng thử lại sau {wait_sec} giây.",
            )

    @staticmethod
    def build_public_id(
        user_id: uuid.UUID,
        target: MediaTarget,
        entity_id: uuid.UUID | None = None,
    ) -> tuple[str, bool]:
        """Constructs the Cloudinary `public_id` path and determines whether to overwrite in place.

        Single-value profile assets (`USER_AVATAR`, `USER_BANNER`, and `FANDOM_AVATAR`/`FANDOM_BANNER`
        with an `entity_id`) use a deterministic `public_id` with `overwrite=True` so that replacing
        an avatar or banner automatically overwrites the previous asset without leaving orphan files.

        Args:
            user_id (uuid.UUID): Authenticated user's ID.
            target (MediaTarget): Upload target category.
            entity_id (uuid.UUID | None): Optional Fandom ID or Channel ID.

        Returns:
            tuple[str, bool]: `(public_id, overwrite)` pair.
        """
        uid_str = str(user_id)
        ent_str = str(entity_id) if entity_id else uid_str
        unique_token = uuid.uuid4().hex[:12]

        if target == MediaTarget.USER_AVATAR:
            return f"fanspace/users/{uid_str}/avatar", True
        if target == MediaTarget.USER_BANNER:
            return f"fanspace/users/{uid_str}/banner", True
        if target == MediaTarget.FANDOM_AVATAR:
            if entity_id:
                return f"fanspace/fandoms/{ent_str}/avatar", True
            return f"fanspace/users/{uid_str}/fandom_avatars/{unique_token}", False
        if target == MediaTarget.FANDOM_BANNER:
            if entity_id:
                return f"fanspace/fandoms/{ent_str}/banner", True
            return f"fanspace/users/{uid_str}/fandom_banners/{unique_token}", False
        if target == MediaTarget.FANDOM_ILLUSTRATION:
            scope = f"fandoms/{ent_str}" if entity_id else f"users/{uid_str}"
            return f"fanspace/{scope}/illustrations/{unique_token}", False

        # CHAT_ATTACHMENT
        scope = f"channels/{ent_str}" if entity_id else f"users/{uid_str}"
        return f"fanspace/chat/{scope}/{unique_token}", False

    @staticmethod
    def build_video_thumbnail_url(video_url: str) -> str | None:
        """Derives an automatic JPEG frame thumbnail URL from a Cloudinary video delivery URL.

        Args:
            video_url (str): Cloudinary HTTPS video URL.

        Returns:
            str | None: Thumbnail JPEG URL extracted at second 1, or None if not applicable.
        """
        if "/video/upload/" not in video_url:
            return None
        with_offset = video_url.replace("/video/upload/", "/video/upload/so_1/", 1)
        base, _ = with_offset.rsplit(".", 1)
        return f"{base}.jpg"

    @classmethod
    async def upload_file(
        cls,
        file: UploadFile,
        user_id: uuid.UUID,
        target: MediaTarget,
        redis: aioredis.Redis,
        entity_id: uuid.UUID | None = None,
    ) -> MediaUploadResponse:
        """Validates, rate-limits, and uploads an image or short video to Cloudinary.

        Args:
            file (UploadFile): Incoming multipart file upload.
            user_id (uuid.UUID): ID of the authenticated user uploading the file.
            target (MediaTarget): Target usage context.
            redis (aioredis.Redis): Redis client for rate limiting.
            entity_id (uuid.UUID | None): Optional target entity UUID (e.g., fandom_id).

        Returns:
            MediaUploadResponse: Metadata and CDN URLs of the uploaded asset.
        """
        await cls.check_upload_rate_limit(redis, user_id)

        content = await file.read()
        resource_type, detected_ext = cls.validate_file_bytes(content, target)
        cls.configure_cloudinary()

        public_id, overwrite = cls.build_public_id(user_id, target, entity_id)

        upload_options: dict = {
            "public_id": public_id,
            "resource_type": resource_type.value,
            "overwrite": overwrite,
            "invalidate": True,
        }

        try:
            result = await asyncio.to_thread(
                cloudinary.uploader.upload,
                io.BytesIO(content),
                **upload_options,
            )
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=f"Lỗi tải tệp lên dịch vụ lưu trữ đám mây Cloudinary: {str(exc)}",
            )

        duration = result.get("duration")
        if (
            resource_type == MediaResourceType.VIDEO
            and duration is not None
            and float(duration) > settings.MEDIA_MAX_VIDEO_DURATION_SECONDS
        ):
            # Immediately delete the oversized duration video from Cloudinary
            await asyncio.to_thread(
                cloudinary.uploader.destroy,
                result.get("public_id", public_id),
                resource_type="video",
                invalidate=True,
            )
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Thời lượng video vượt quá giới hạn cho phép (tối đa {int(settings.MEDIA_MAX_VIDEO_DURATION_SECONDS)} giây).",
            )

        secure_url = result["secure_url"]
        thumbnail_url = (
            cls.build_video_thumbnail_url(secure_url)
            if resource_type == MediaResourceType.VIDEO
            else None
        )

        return MediaUploadResponse(
            success=True,
            url=secure_url,
            public_id=result.get("public_id", public_id),
            resource_type=resource_type,
            format=result.get("format", detected_ext),
            bytes=result.get("bytes", len(content)),
            width=result.get("width"),
            height=result.get("height"),
            duration=duration,
            thumbnail_url=thumbnail_url,
        )

    @staticmethod
    def extract_cloudinary_asset_info(url: str | None) -> tuple[str, MediaResourceType] | None:
        """Extracts `(public_id, resource_type)` from a FanSpace Cloudinary delivery URL.

        Safely returns `None` for external URLs (such as Google OAuth avatars) or URLs
        belonging to a different Cloudinary cloud name.

        Args:
            url (str | None): Candidate media URL.

        Returns:
            tuple[str, MediaResourceType] | None: `(public_id, resource_type)` if owned by this system, else None.
        """
        if not url or not isinstance(url, str):
            return None
        match = _CLOUDINARY_URL_PATTERN.match(url.strip())
        if not match:
            return None
        cloud_name = match.group("cloud_name")
        if settings.CLOUDINARY_CLOUD_NAME and cloud_name != settings.CLOUDINARY_CLOUD_NAME:
            return None
        r_type = (
            MediaResourceType.VIDEO
            if match.group("resource_type") == "video"
            else MediaResourceType.IMAGE
        )
        return match.group("public_id"), r_type

    @classmethod
    async def delete_by_url(cls, url: str | None) -> MediaDeleteResponse:
        """Deletes a Cloudinary asset identified by its delivery URL.

        Passes the correct `resource_type` ('image' or 'video') so both images and short
        videos are properly destroyed on Cloudinary.

        Args:
            url (str | None): Delivery URL of the asset to remove.

        Returns:
            MediaDeleteResponse: Result status and deleted `public_id`.
        """
        info = cls.extract_cloudinary_asset_info(url)
        if not info:
            return MediaDeleteResponse(
                success=False,
                message="URL không thuộc kho lưu trữ Cloudinary của hệ thống nên được bỏ qua.",
                public_id=None,
                resource_type=None,
            )

        public_id, resource_type = info
        cls.configure_cloudinary()

        try:
            res = await asyncio.to_thread(
                cloudinary.uploader.destroy,
                public_id,
                resource_type=resource_type.value,
                invalidate=True,
            )
            destroyed = res.get("result") == "ok"
            return MediaDeleteResponse(
                success=destroyed,
                message="Đã xóa tệp khỏi Cloudinary thành công." if destroyed else f"Trạng thái xóa: {res.get('result')}",
                public_id=public_id,
                resource_type=resource_type,
            )
        except Exception as exc:
            return MediaDeleteResponse(
                success=False,
                message=f"Không thể xóa tệp trên Cloudinary: {str(exc)}",
                public_id=public_id,
                resource_type=resource_type,
            )

    @classmethod
    async def cleanup_replaced_urls(
        cls,
        old_urls: list[str | None],
        new_urls: list[str | None],
    ) -> None:
        """Asynchronously deletes old Cloudinary assets that were removed or replaced after a DB update.

        Compares `public_id` sets between `old_urls` and `new_urls` so that assets overwritten
        in-place with the same `public_id` are never accidentally deleted.

        Args:
            old_urls (list[str | None]): Previous media URLs stored on the entity before update.
            new_urls (list[str | None]): New media URLs committed to the database.
        """
        new_public_ids = {
            info[0]
            for u in new_urls
            if u and (info := cls.extract_cloudinary_asset_info(u)) is not None
        }

        for old_url in old_urls:
            if not old_url:
                continue
            info = cls.extract_cloudinary_asset_info(old_url)
            if info and info[0] not in new_public_ids:
                await cls.delete_by_url(old_url)

    @staticmethod
    def validate_illustration_urls(urls: list[str] | None) -> list[str] | None:
        """Validates Fandom `illustration_urls` constraints (max 5 items, max 1 short video).

        Args:
            urls (list[str] | None): List of media URLs submitted for a fandom profile.

        Returns:
            list[str] | None: Cleaned list of URLs.

        Raises:
            HTTPException: 400 Bad Request if count > 5 or video count > 1.
        """
        if urls is None:
            return None

        cleaned = [u.strip() for u in urls if u and u.strip()]
        if len(cleaned) > settings.MEDIA_MAX_ILLUSTRATION_COUNT:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Hồ sơ Fandom chỉ được phép đính kèm tối đa {settings.MEDIA_MAX_ILLUSTRATION_COUNT} tệp minh họa.",
            )

        video_count = sum(
            1
            for u in cleaned
            if "/video/upload/" in u or u.lower().endswith((".mp4", ".webm"))
        )
        if video_count > settings.MEDIA_MAX_ILLUSTRATION_VIDEOS:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Danh sách minh họa Fandom chỉ được phép chứa tối đa {settings.MEDIA_MAX_ILLUSTRATION_VIDEOS} video ngắn (Short Video).",
            )

        return cleaned
