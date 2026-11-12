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


MAX_FANDOMS_PER_OWNER: int = 5


class FandomProfileUpdate(BaseModel):
    """Payload for updating public profile and appearance metadata of a fandom."""
    name: str | None = Field(
        None,
        min_length=2,
        max_length=100,
        description="Tên cộng đồng fandom mới",
        examples=["Sơn Tùng M-TP Fanclub"],
    )
    description: str | None = Field(
        None,
        max_length=5000,
        description="Mô tả giới thiệu chi tiết về cộng đồng",
    )
    category: str | None = Field(
        None,
        max_length=50,
        description="Chủ đề phân loại của fandom",
    )
    avatar_url: str | None = Field(None, description="URL ảnh đại diện mới của fandom")
    banner_url: str | None = Field(None, description="URL ảnh bìa banner mới của fandom")
    illustration_urls: list[str] | None = Field(
        None,
        description="Danh sách URL ảnh hoặc video ngắn minh họa (tối đa 5 tệp, tối đa 1 video ngắn)",
    )
    admission_mode: str | None = Field(
        None,
        pattern=r"^(OPEN|APPROVAL)$",
        description="Chế độ gia nhập: 'OPEN' (tự do) hoặc 'APPROVAL' (phê duyệt)",
    )
    rules_tos: str | None = Field(
        None,
        max_length=10000,
        description="Nội quy và điều khoản nội bộ của fandom",
    )


class FandomVisibilityUpdate(BaseModel):
    """Payload for updating public visibility of a fandom space."""
    is_public: bool = Field(..., description="Trạng thái hiển thị công khai (True) hoặc riêng tư (False)")


class FandomDeleteRequest(BaseModel):
    """Payload for confirming deletion of a fandom community."""
    password: str | None = Field(None, description="Mật khẩu xác nhận của Chủ sở hữu")
    otp: str | None = Field(None, description="Mã OTP xác nhận gửi về email (đối với tài khoản chưa thiết lập mật khẩu)")


class FandomDeleteResponse(BaseModel):
    """Response returned upon successfully deleting a fandom space."""
    success: bool = Field(default=True, description="Trạng thái thực thi")
    message: str = Field(..., description="Thông báo kết quả")
    fandom_id: uuid.UUID = Field(..., description="ID định danh của fandom vừa bị xóa")


class MyFandomsResponse(BaseModel):
    """Comprehensive aggregation of current user's fandom participations."""
    joined: list[FandomSummary] = Field(default_factory=list, description="Danh sách Fandom người dùng đang là thành viên")
    managed: list[FandomSummary] = Field(default_factory=list, description="Danh sách Fandom người dùng đang làm Chủ sở hữu")
    pending_requests: list[FandomJoinRequestOut] = Field(default_factory=list, description="Danh sách đơn xin gia nhập đang chờ duyệt")
    quota_used: int = Field(default=0, description="Số lượng Fandom người dùng đang sở hữu")
    max_quota: int = Field(default=MAX_FANDOMS_PER_OWNER, description="Giới hạn số Fandom tối đa được sở hữu cùng lúc")


class RoleCreate(BaseModel):
    """Payload for creating a new custom role."""
    name: str = Field(..., min_length=1, max_length=50, description="Tên vai trò")
    color_hex: str = Field(default="#808080", pattern=r"^#[0-9a-fA-F]{6}$", description="Mã màu HEX hiển thị")
    priority: int = Field(default=0, ge=0, le=1000, description="Độ ưu tiên thứ bậc (càng cao càng lớn)")
    permissions_bitmask: int = Field(default=0, ge=0, description="Tổ hợp quyền hạn bitmask O(1)")


class RoleUpdate(BaseModel):
    """Payload for updating an existing role."""
    name: str | None = Field(None, min_length=1, max_length=50, description="Tên vai trò mới")
    color_hex: str | None = Field(None, pattern=r"^#[0-9a-fA-F]{6}$", description="Mã màu HEX mới")
    priority: int | None = Field(None, ge=0, le=1000, description="Độ ưu tiên thứ bậc mới")
    permissions_bitmask: int | None = Field(None, ge=0, description="Tổ hợp quyền hạn bitmask mới")


class RoleOut(BaseModel):
    """Public projection of a fandom role."""
    id: uuid.UUID = Field(..., description="ID vai trò")
    fandom_id: uuid.UUID = Field(..., description="ID Fandom")
    name: str = Field(..., description="Tên vai trò")
    color_hex: str = Field(..., description="Mã màu HEX")
    priority: int = Field(..., description="Độ ưu tiên thứ bậc")
    permissions_bitmask: int = Field(..., description="Bitmask quyền hạn")
    is_preset_mod: bool = Field(default=False, description="Là vai trò Mod định sẵn")
    is_membership_tier: bool = Field(default=False, description="Là gói Membership trả phí")
    tier_level: int | None = Field(default=None, description="Cấp bậc gói hội viên (1-4)")
    icon_url: str | None = Field(default=None, description="Icon/Huy hiệu gói hội viên")
    price_fiat_vnd: int | None = Field(default=None, description="Đơn giá gói hội viên (VNĐ)")
    duration_days: int | None = Field(default=None, description="Thời hạn gói hội viên (ngày)")
    created_at: datetime = Field(..., description="Thời điểm tạo")

    model_config = {"from_attributes": True}


class PresetModAssign(BaseModel):
    """Payload for assigning a preset moderator role to a member."""
    user_id: uuid.UUID = Field(..., description="ID thành viên được bổ nhiệm")
    preset_type: str = Field(
        ...,
        pattern=r"^(CO_HOST|CHAT_MODERATOR|VOICE_MODERATOR)$",
        description="Loại vai trò Mod định sẵn: CO_HOST, CHAT_MODERATOR, VOICE_MODERATOR",
    )


class MemberRoleAssign(BaseModel):
    """Payload for synchronizing assigned custom roles of a member."""
    role_ids: list[uuid.UUID] = Field(default_factory=list, description="Danh sách ID vai trò được gán")


class FandomMemberOut(BaseModel):
    """Comprehensive representation of a fandom member with roles and status."""
    user_id: uuid.UUID = Field(..., description="ID người dùng")
    username: str = Field(..., description="Tên tài khoản")
    display_name: str = Field(..., description="Tên hiển thị")
    avatar_url: str | None = Field(None, description="Ảnh đại diện")
    status: str = Field(..., description="Trạng thái: ACTIVE, MUTED, BANNED")
    muted_until: datetime | None = Field(None, description="Thời điểm hết hạn tắt tiếng")
    joined_at: datetime = Field(..., description="Thời điểm gia nhập")
    roles: list[RoleOut] = Field(default_factory=list, description="Danh sách vai trò của thành viên")

    model_config = {"from_attributes": True}


class MemberKickRequest(BaseModel):
    """Payload for kicking a member from fandom."""
    reason: str | None = Field(None, max_length=255, description="Lý do trục xuất")


class MemberBanRequest(BaseModel):
    """Payload for permanently banning a user from fandom."""
    reason: str | None = Field(None, max_length=255, description="Lý do cấm vĩnh viễn")


class MemberMuteRequest(BaseModel):
    """Payload for muting a member in fandom."""
    duration_hours: int = Field(default=24, ge=1, le=8760, description="Thời lượng tắt tiếng (giờ)")
    reason: str | None = Field(None, max_length=255, description="Lý do tắt tiếng")


class ModerationActionResponse(BaseModel):
    """Response returned upon performing a member moderation action."""
    success: bool = Field(default=True, description="Trạng thái thực thi")
    message: str = Field(..., description="Thông báo kết quả")
    action: str = Field(..., description="Hành động: KICK, BAN, UNBAN, MUTE, UNMUTE")
    user_id: uuid.UUID = Field(..., description="ID người dùng bị xử phạt")

