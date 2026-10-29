"""Fandom Management and Public Discovery API Router.

Exposes endpoints for creating fandom communities, searching and sorting the
public fandom directory, filtering by category, and viewing detailed community
profiles with optional authentication context.
"""

import redis.asyncio as aioredis
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.redis import get_redis
from app.modules.identity.models import User
from app.modules.identity.service import get_current_user, get_optional_current_user
from app.modules.fandom.schemas import (
    FandomCreate,
    FandomCreateResponse,
    FandomDetail,
    FandomSortBy,
    FandomSummary,
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
    - **Minh họa đa phương tiện**: Hỗ trợ đính kèm tối đa 5 tệp `illustration_urls` (tối đa 1 short video).
    - **Cài đặt chế độ tham gia**: Hỗ trợ chế độ mở tự do (`OPEN`) hoặc phê duyệt xét tuyển (`APPROVAL`).
    """,
    responses={
        400: {"description": "Slug fandom đã tồn tại hoặc danh sách tệp minh họa vượt quá giới hạn"},
        401: {"description": "Chưa xác thực phiên đăng nhập"},
    },
)
async def create_fandom(
    data: FandomCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    """Creates a new fandom space owned by the authenticated user."""
    fandom = await FandomService.create_fandom(db, current_user, data, redis=redis)
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
    Tìm kiếm, lọc và sắp xếp các cộng đồng Fandom công khai đang hoạt động:
    - **Tìm kiếm thông minh (`search`)**: Không phân biệt chữ hoa/thường và dấu tiếng Việt trên tên Fandom (`name`), đường dẫn (`slug`), tên hiển thị/username của Chủ Fandom (`owner_name`) và mã định danh Chủ Fandom (`owner_id`).
    - **Lọc theo chủ đề (`category`)**: Lọc chính xác theo danh mục (Âm nhạc, Thần tượng (Idol), Game & Esports, Phim ảnh & Anime, Thể thao, Công nghệ...).
    - **Sắp xếp (`sort_by`)**:
      - `popular` *(mặc định)*: Sắp xếp theo số lượng thành viên giảm dần.
      - `newest`: Sắp xếp theo thời gian thành lập mới nhất.
      - `name_asc`: Sắp xếp theo bảng chữ cái từ A đến Z.
    - **Phân trang (`limit`, `offset`)**: Trả về dữ liệu tóm tắt (`FandomSummary` với mô tả cắt gọn tối đa 160 ký tự) kết hợp bộ đệm Redis RAM Cache.
    """,
)
async def list_public_fandoms(
    search: str | None = Query(
        None,
        max_length=100,
        description="Từ khóa tìm kiếm (tên Fandom, slug, tên chủ sở hữu hoặc ID chủ sở hữu)",
    ),
    category: str | None = Query(None, max_length=50, description="Lọc theo danh mục chủ đề"),
    sort_by: FandomSortBy = Query(
        FandomSortBy.POPULAR,
        description="Tiêu chí sắp xếp: 'popular', 'newest', 'name_asc'",
    ),
    limit: int = Query(20, ge=1, le=50, description="Số lượng kết quả mỗi trang (1 - 50)"),
    offset: int = Query(0, ge=0, le=1000, description="Vị trí bắt đầu phân trang (0 - 1000)"),
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    """Returns a paginated, sorted list of public fandom summary cards."""
    return await FandomService.list_public(
        db=db,
        search=search,
        category=category,
        sort_by=sort_by,
        limit=limit,
        offset=offset,
        redis=redis,
    )


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
    summary="Xem hồ sơ chi tiết của một Fandom công khai",
    description="""
    Trả về toàn bộ thông tin hồ sơ giới thiệu của một Fandom theo `slug`:
    - Bao gồm mô tả đầy đủ (`description`), nội quy (`rules_tos`), bộ tệp minh họa ảnh/short video (`illustration_urls`), và thông tin người sáng lập.
    - Hỗ trợ xác thực tùy chọn (Optional Bearer Token): nếu người xem đã đăng nhập, hệ thống trả về chính xác cờ `is_owner` và `is_member`.
    """,
    responses={
        404: {"description": "Không tìm thấy Fandom tương ứng với slug"},
    },
)
async def get_fandom_preview(
    slug: str,
    current_user: User | None = Depends(get_optional_current_user),
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    """Retrieves full profile metadata for a fandom by its unique slug."""
    return await FandomService.get_preview(
        db=db,
        slug=slug,
        current_user=current_user,
        redis=redis,
    )
