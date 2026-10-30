"""Data Transfer Objects and Pydantic Schemas for Fandom Module.

Defines validation rules, sorting enumerations, summary projections for the
public directory, and full profile schemas for fandom preview screens.
"""

import uuid
from datetime import datetime
from enum import Enum
from pydantic import BaseModel, Field


class FandomSortBy(str, Enum):
    """Supported sorting strategies for the public fandom directory."""
    POPULAR = "popular"
    NEWEST = "newest"
    NAME_ASC = "name_asc"


class FandomCreate(BaseModel):
    """Payload for creating a new fandom space."""
    name: str = Field(
        ...,
        min_length=2,
        max_length=100,
        description="Tên cộng đồng fandom",
        examples=["Sơn Tùng M-TP Official Fanclub"],
    )
    slug: str = Field(
        ...,
        min_length=2,
        max_length=100,
        pattern=r"^[a-z0-9-]+$",
        description="Đường dẫn định danh duy nhất (chỉ gồm chữ thường, số và gạch ngang)",
        examples=["son-tung-mtp"],
    )
    description: str | None = Field(
        None,
        max_length=5000,
        description="Mô tả giới thiệu về cộng đồng",
        examples=["Cộng đồng người hâm mộ chính thức của Sơn Tùng M-TP"],
    )
    category: str = Field(
        default="Âm nhạc",
        max_length=50,
        description="Chủ đề phân loại của fandom",
        examples=["Âm nhạc"],
    )
    avatar_url: str | None = Field(None, description="URL ảnh đại diện của fandom")
    banner_url: str | None = Field(None, description="URL ảnh bìa banner của fandom")
    illustration_urls: list[str] | None = Field(
        default=None,
        description="Danh sách URL ảnh hoặc short video minh họa (tối đa 5 tệp, trong đó tối đa 1 short video)",
    )
    is_public: bool = Field(
        default=True,
        description="Trạng thái hiển thị công khai trên danh mục khám phá",
    )
    admission_mode: str = Field(
        default="OPEN",
        pattern=r"^(OPEN|APPROVAL)$",
        description="Chế độ gia nhập: 'OPEN' (tự do) hoặc 'APPROVAL' (phê duyệt)",
        examples=["OPEN"],
    )
    rules_tos: str | None = Field(
        None,
        max_length=10000,
        description="Quy định và điều khoản nội bộ của fandom",
    )


class FandomCreateResponse(BaseModel):
    """Response returned upon successfully creating a fandom."""
    success: bool = Field(default=True, description="Trạng thái thực thi")
    message: str = Field(..., description="Thông báo kết quả")
    fandom_id: uuid.UUID = Field(..., description="ID định danh duy nhất của fandom vừa tạo")
    slug: str = Field(..., description="Slug định danh của fandom")


class FandomSummary(BaseModel):
    """Lightweight summary projection returned in the public fandom directory."""
    id: uuid.UUID = Field(..., description="ID định danh fandom")
    name: str = Field(..., description="Tên fandom")
    slug: str = Field(..., description="Slug định danh fandom")
    description: str | None = Field(
        None,
        description="Mô tả tóm tắt về fandom",
    )
    category: str = Field(..., description="Danh mục fandom")
    avatar_url: str | None = Field(None, description="Ảnh đại diện")
    banner_url: str | None = Field(None, description="Ảnh bìa banner")
    admission_mode: str = Field(default="OPEN", description="Chế độ tham gia ('OPEN' hoặc 'APPROVAL')")
    member_count: int = Field(..., description="Số lượng thành viên hiện tại")
    owner_id: uuid.UUID = Field(..., description="ID người sáng lập")
    owner_name: str = Field(..., description="Tên hiển thị của người sáng lập")
    created_at: datetime = Field(..., description="Thời điểm thành lập")

    model_config = {"from_attributes": True}


class FandomDetail(BaseModel):
    """Complete profile metadata returned when viewing a specific fandom profile."""
    id: uuid.UUID = Field(..., description="ID định danh fandom")
    name: str = Field(..., description="Tên fandom")
    slug: str = Field(..., description="Slug định danh fandom")
    description: str | None = Field(None, description="Bài giới thiệu chi tiết đầy đủ của fandom")
    category: str = Field(..., description="Danh mục")
    avatar_url: str | None = Field(None, description="Ảnh đại diện")
    banner_url: str | None = Field(None, description="Ảnh bìa banner")
    illustration_urls: list[str] = Field(
        default_factory=list,
        description="Danh sách URL ảnh và short video minh họa giới thiệu fandom",
    )
    is_public: bool = Field(default=True, description="Trạng thái công khai của fandom")
    admission_mode: str = Field(..., description="Chế độ tham gia ('OPEN' hoặc 'APPROVAL')")
    rules_tos: str | None = Field(None, description="Nội quy và điều khoản tham gia fandom")
    member_count: int = Field(..., description="Số lượng thành viên")
    owner_id: uuid.UUID = Field(..., description="ID người sáng lập")
    owner_name: str = Field(..., description="Tên hiển thị của người sáng lập")
    owner_username: str | None = Field(None, description="Username định danh của người sáng lập")
    owner_avatar_url: str | None = Field(None, description="Ảnh đại diện của người sáng lập")
    is_owner: bool = Field(default=False, description="True nếu người đang xem là chủ sở hữu fandom")
    is_member: bool = Field(default=False, description="True nếu người đang xem đã là thành viên của fandom")
    is_pending_request: bool = Field(default=False, description="True nếu người đang xem có yêu cầu gia nhập đang chờ duyệt")
    created_at: datetime = Field(..., description="Thời điểm thành lập")

    model_config = {"from_attributes": True}


class FandomJoinResponse(BaseModel):
    """Response returned upon joining or submitting a join request."""
    success: bool = Field(default=True, description="Trạng thái thực thi")
    message: str = Field(..., description="Thông báo kết quả")
    status: str = Field(..., description="Trạng thái: 'JOINED' hoặc 'REQUEST_SUBMITTED'")
    fandom_id: uuid.UUID = Field(..., description="ID định danh fandom")
    slug: str = Field(..., description="Slug định danh fandom")


class FandomLeaveResponse(BaseModel):
    """Response returned upon successfully leaving a fandom."""
    success: bool = Field(default=True, description="Trạng thái thực thi")
    message: str = Field(..., description="Thông báo kết quả")
    fandom_id: uuid.UUID = Field(..., description="ID định danh fandom")


class FandomCancelRequestResponse(BaseModel):
    """Response returned upon cancelling a pending join request."""
    success: bool = Field(default=True, description="Trạng thái thực thi")
    message: str = Field(..., description="Thông báo kết quả")
    fandom_id: uuid.UUID = Field(..., description="ID định danh fandom")


class FandomInviteCreate(BaseModel):
    """Payload for generating an invite link / code."""
    max_uses: int | None = Field(None, ge=1, le=100000, description="Số lượt sử dụng tối đa (None nếu không giới hạn)")
    expires_in_hours: int | None = Field(None, ge=1, le=8760, description="Thời hạn hiệu lực theo giờ (None nếu vĩnh viễn)")


class FandomInviteOut(BaseModel):
    """Public representation of an invite code."""
    code: str = Field(..., description="Mã mời duy nhất (8 ký tự)")
    fandom_id: uuid.UUID = Field(..., description="ID fandom")
    fandom_name: str = Field(..., description="Tên fandom")
    fandom_slug: str = Field(..., description="Slug fandom")
    max_uses: int | None = Field(None, description="Số lượt dùng tối đa")
    uses_count: int = Field(default=0, description="Số lượt đã dùng")
    expires_at: datetime | None = Field(None, description="Thời điểm hết hạn")
    created_at: datetime = Field(..., description="Thời điểm tạo mã")

    model_config = {"from_attributes": True}


class FandomJoinByInviteRequest(BaseModel):
    """Payload for joining via an invite code."""
    code: str = Field(..., min_length=4, max_length=32, description="Mã mời Fandom")


class FandomJoinRequestOut(BaseModel):
    """Join request representation for applicants and reviewing owners."""
    id: uuid.UUID = Field(..., description="ID yêu cầu")
    fandom_id: uuid.UUID = Field(..., description="ID fandom")
    fandom_name: str = Field(..., description="Tên fandom")
    fandom_slug: str = Field(..., description="Slug fandom")
    fandom_avatar_url: str | None = Field(None, description="Avatar của fandom")
    user_id: uuid.UUID = Field(..., description="ID người gửi yêu cầu")
    username: str = Field(..., description="Username người gửi yêu cầu")
    display_name: str = Field(..., description="Tên hiển thị người gửi yêu cầu")
    avatar_url: str | None = Field(None, description="Ảnh đại diện người gửi yêu cầu")
    status: str = Field(..., description="Trạng thái: PENDING, APPROVED, REJECTED")
    answers_payload: dict | None = Field(None, description="Câu trả lời khảo sát gia nhập (nếu có)")
    created_at: datetime = Field(..., description="Thời điểm gửi yêu cầu")

    model_config = {"from_attributes": True}


class FandomJoinRequestReview(BaseModel):
    """Payload for approving or rejecting a join request."""
    action: str = Field(..., pattern=r"^(APPROVE|REJECT)$", description="Hành động: 'APPROVE' hoặc 'REJECT'")


class MyFandomsResponse(BaseModel):
    """Comprehensive aggregation of current user's fandom participations."""
    joined: list[FandomSummary] = Field(default_factory=list, description="Danh sách Fandom người dùng đang là thành viên")
    managed: list[FandomSummary] = Field(default_factory=list, description="Danh sách Fandom người dùng đang làm Chủ sở hữu")
    pending_requests: list[FandomJoinRequestOut] = Field(default_factory=list, description="Danh sách đơn xin gia nhập đang chờ duyệt")
