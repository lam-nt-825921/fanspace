"""Fandom Management and Public Discovery API Router.

This module exposes endpoints for creating fandom communities, searching the public
fandom directory, filtering by category, and previewing community metadata.
"""

from fastapi import APIRouter, Depends, Query, status, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.modules.identity.models import User
from app.modules.identity.service import get_current_user
from app.modules.fandom.schemas import (
    FandomCreate,
    FandomCreateResponse,
    FandomSummary,
    FandomDetail,
)
from app.modules.fandom.service import FandomService

fandom_router = APIRouter(prefix="/api/v1/fandoms", tags=["Fandoms"])

POPULAR_CATEGORIES = [
    "Tất cả",
    "Âm nhạc",
    "Thần tượng (Idol)",
    "Game & Esports",
    "Phim ảnh & Anime",
    "Thể thao",
    "Công nghệ",
]


@fandom_router.post(
    "",
    response_model=FandomCreateResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Khởi tạo không gian Fandom mới",
    description="""
    Tạo một cộng đồng Fandom mới:
    - **Yêu cầu đăng nhập**: Người tạo tự động trở thành Chủ sở hữu (Owner) của Fandom.
    - **Slug duy nhất**: Tên định danh slug không được trùng với fandom đã tồn tại.
    - **Cài đặt chế độ tham gia**: Hỗ trợ chế độ mở tự do (`OPEN`) hoặc phê duyệt xét tuyển (`APPROVAL`).
    """,
    responses={
        400: {"description": "Slug fandom đã tồn tại hoặc dữ liệu đầu vào không hợp lệ"},
        401: {"description": "Chưa đăng nhập"},
    },
)
async def create_fandom(
    data: FandomCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Creates a new fandom space owned by the authenticated user."""
    fandom = await FandomService.create_fandom(db, current_user, data)
    return FandomCreateResponse(
        success=True,
        message=f"Không gian Fandom '{fandom.name}' đã được khởi tạo thành công.",
        fandom_id=fandom.id,
        slug=fandom.slug,
    )


@fandom_router.get(
    "/public",
    response_model=list[FandomSummary],
    summary="Khám phá danh mục Fandom công khai",
    description="""
    Tìm kiếm và khám phá các cộng đồng Fandom đang hoạt động:
    - **Tìm kiếm từ khóa**: Tìm theo tên, slug hoặc mô tả.
    - **Lọc theo chủ đề**: Lọc chính xác theo danh mục (Âm nhạc, Idol, Game, Anime, Thể thao...).
    - **Phân trang**: Giới hạn kết quả trả về (`limit`).
    """,
)
async def list_public_fandoms(
    search: str | None = Query(None, description="Từ khóa tìm kiếm theo tên, slug hoặc mô tả"),
    category: str | None = Query(None, description="Lọc theo danh mục"),
    limit: int = Query(20, ge=1, le=100, description="Số lượng kết quả tối đa trả về"),
    db: AsyncSession = Depends(get_db),
):
    """Returns a list of public fandom communities matching search and category filters."""
    return await FandomService.list_public(db, search, category, limit)


@fandom_router.get(
    "/public/categories",
    response_model=list[str],
    summary="Lấy danh sách các chủ đề phân loại Fandom",
    description="Trả về danh sách các danh mục tiêu biểu có sẵn trong hệ thống.",
)
async def get_categories():
    """Returns the predefined list of popular fandom categories."""
    return POPULAR_CATEGORIES


@fandom_router.get(
    "/{slug}/preview",
    response_model=FandomDetail,
    summary="Xem trước thông tin không gian Fandom (Public Preview)",
    description="Xem thông tin chi tiết công khai của một Fandom bằng slug mà không bắt buộc đăng nhập.",
    responses={
        404: {"description": "Không tìm thấy Fandom tương ứng với slug"},
    },
)
async def get_fandom_preview(
    slug: str,
    db: AsyncSession = Depends(get_db),
):
    """Retrieves public preview metadata for a fandom by its unique slug."""
    return await FandomService.get_preview(db, slug, current_user=None)
