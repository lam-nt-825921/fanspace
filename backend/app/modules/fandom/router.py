from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.modules.identity.models import User
from app.modules.identity.service import get_current_user
from app.modules.fandom.schemas import FandomCreate, FandomSummary, FandomDetail
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


@fandom_router.post("", response_model=dict, status_code=status.HTTP_201_CREATED)
async def create_fandom(
    data: FandomCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    fandom = await FandomService.create_fandom(db, current_user, data)
    return {
        "success": True,
        "message": f"Không gian Fandom '{fandom.name}' đã được khởi tạo thành công.",
        "fandom_id": fandom.id,
        "slug": fandom.slug,
    }


@fandom_router.get("/public", response_model=list[FandomSummary])
async def list_public_fandoms(
    search: str | None = Query(None, description="Từ khóa tìm kiếm theo tên, slug hoặc mô tả"),
    category: str | None = Query(None, description="Lọc theo danh mục"),
    limit: int = Query(20, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
):
    return await FandomService.list_public(db, search, category, limit)


@fandom_router.get("/public/categories", response_model=list[str])
async def get_categories():
    return POPULAR_CATEGORIES


@fandom_router.get("/{slug}/preview", response_model=FandomDetail)
async def get_fandom_preview(
    slug: str,
    db: AsyncSession = Depends(get_db),
):
    # Preview endpoint can be viewed without logging in
    return await FandomService.get_preview(db, slug, current_user=None)
