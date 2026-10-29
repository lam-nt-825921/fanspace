"""Pydantic Schemas and Enumerations for Shared Media Upload Service."""

from enum import Enum
from pydantic import BaseModel, Field


class MediaTarget(str, Enum):
    """Target usage context determining file format, size quota, and storage folder."""
    USER_AVATAR = "USER_AVATAR"
    USER_BANNER = "USER_BANNER"
    FANDOM_AVATAR = "FANDOM_AVATAR"
    FANDOM_BANNER = "FANDOM_BANNER"
    FANDOM_ILLUSTRATION = "FANDOM_ILLUSTRATION"
    CHAT_ATTACHMENT = "CHAT_ATTACHMENT"


class MediaResourceType(str, Enum):
    """Cloudinary media asset classification."""
    IMAGE = "image"
    VIDEO = "video"


class MediaUploadResponse(BaseModel):
    """Standardized response returned after uploading a media asset to Cloudinary."""
    success: bool = Field(default=True, description="Trạng thái tải tệp lên thành công")
    url: str = Field(..., description="Đường dẫn HTTPS công khai trên CDN của tệp media")
    public_id: str = Field(..., description="Mã định danh tài nguyên duy nhất trên Cloudinary")
    resource_type: MediaResourceType = Field(..., description="Phân loại tài nguyên ('image' hoặc 'video')")
    format: str = Field(..., description="Định dạng tệp thực tế (jpg, png, webp, mp4, webm)")
    bytes: int = Field(..., description="Kích thước tệp tính bằng byte")
    width: int | None = Field(None, description="Chiều rộng khung hình (px)")
    height: int | None = Field(None, description="Chiều cao khung hình (px)")
    duration: float | None = Field(None, description="Thời lượng tính bằng giây (chỉ áp dụng cho video)")
    thumbnail_url: str | None = Field(
        None,
        description="URL ảnh xem trước (thumbnail) tự động trích xuất nếu tệp tải lên là short video",
    )


class MediaDeleteRequest(BaseModel):
    """Payload to delete a previously uploaded Cloudinary media asset by its URL."""
    url: str = Field(
        ...,
        min_length=10,
        description="Đường dẫn URL Cloudinary của tệp ảnh hoặc video cần xóa",
        examples=["https://res.cloudinary.com/djioawkmo/image/upload/v1730000000/fanspace/users/123/avatar.webp"],
    )


class MediaDeleteResponse(BaseModel):
    """Response returned after deleting a media asset from Cloudinary."""
    success: bool = Field(..., description="True nếu tệp đã được xóa khỏi Cloudinary")
    message: str = Field(..., description="Thông báo kết quả xóa tệp")
    public_id: str | None = Field(None, description="Mã định danh tài nguyên đã xử lý")
    resource_type: MediaResourceType | None = Field(None, description="Loại tài nguyên đã xóa")
