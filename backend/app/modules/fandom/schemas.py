"""Data Transfer Objects and Pydantic Schemas for Fandom Module.

This module defines validation rules and serialization schemas for creating,
discovering, and inspecting fandom communities.
"""

import uuid
from datetime import datetime
from pydantic import BaseModel, Field


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
    admission_mode: str = Field(
        default="OPEN",
        pattern=r"^(OPEN|APPROVAL)$",
        description="Chế độ gia nhập: 'OPEN' (tự do) hoặc 'APPROVAL' (phê duyệt)",
        examples=["OPEN"],
    )
    rules_tos: str | None = Field(None, description="Quy định và điều khoản nội bộ của fandom")


class FandomCreateResponse(BaseModel):
    """Response returned upon successfully creating a fandom."""
    success: bool = Field(default=True, description="Trạng thái thực thi")
    message: str = Field(..., description="Thông báo kết quả")
    fandom_id: uuid.UUID = Field(..., description="ID định danh duy nhất của fandom vừa tạo")
    slug: str = Field(..., description="Slug định danh của fandom")


class FandomSummary(BaseModel):
    """Summary item displayed in the public fandom directory."""
    id: uuid.UUID = Field(..., description="ID định danh fandom")
    name: str = Field(..., description="Tên fandom")
    slug: str = Field(..., description="Slug định danh fandom")
    description: str | None = Field(None, description="Mô tả tóm tắt")
    category: str = Field(..., description="Danh mục fandom")
    avatar_url: str | None = Field(None, description="Ảnh đại diện")
    banner_url: str | None = Field(None, description="Ảnh bìa banner")
    member_count: int = Field(..., description="Số lượng thành viên hiện tại")
    owner_name: str = Field(..., description="Tên người sáng lập")
    created_at: datetime = Field(..., description="Thời điểm thành lập")

    model_config = {"from_attributes": True}


class FandomDetail(BaseModel):
    """Detailed metadata for fandom preview and home screens."""
    id: uuid.UUID = Field(..., description="ID định danh fandom")
    name: str = Field(..., description="Tên fandom")
    slug: str = Field(..., description="Slug định danh fandom")
    description: str | None = Field(None, description="Mô tả chi tiết")
    category: str = Field(..., description="Danh mục")
    avatar_url: str | None = Field(None, description="Ảnh đại diện")
    banner_url: str | None = Field(None, description="Ảnh bìa banner")
    admission_mode: str = Field(..., description="Chế độ tham gia ('OPEN' hoặc 'APPROVAL')")
    rules_tos: str | None = Field(None, description="Nội quy fandom")
    member_count: int = Field(..., description="Số thành viên")
    owner_id: uuid.UUID = Field(..., description="ID người sáng lập")
    owner_name: str = Field(..., description="Tên người sáng lập")
    is_owner: bool = Field(default=False, description="True nếu người dùng hiện tại là chủ sở hữu")
    is_member: bool = Field(default=False, description="True nếu người dùng hiện tại đã là thành viên")
    created_at: datetime = Field(..., description="Thời điểm thành lập")

    model_config = {"from_attributes": True}
