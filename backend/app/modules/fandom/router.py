"""Fandom Management and Public Discovery API Router.

Exposes endpoints for creating fandom communities, searching and sorting the
public fandom directory, filtering by category, and viewing detailed community
profiles with optional authentication context.
"""

import uuid
import redis.asyncio as aioredis
from fastapi import APIRouter, Body, Depends, Query, status
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
    FandomJoinResponse,
    FandomLeaveResponse,
    FandomCancelRequestResponse,
    FandomInviteCreate,
    FandomInviteOut,
    FandomJoinByInviteRequest,
    FandomJoinRequestOut,
    FandomJoinRequestReview,
    MyFandomsResponse,
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
    "/me/memberships",
    response_model=MyFandomsResponse,
    summary="Lấy danh sách Fandom của tôi",
    description="Trả về các Fandom người dùng đang tham gia, đang làm Chủ sở hữu và các đơn xin gia nhập đang chờ duyệt.",
)
@fandom_router.get(
    "/me/fandoms",
    response_model=MyFandomsResponse,
    summary="Lấy danh sách Fandom của tôi (alias)",
    description="Alias của /me/memberships.",
)
async def get_my_fandoms(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Retrieves joined, managed, and pending fandoms for the authenticated user."""
    return await FandomService.get_my_fandoms(db, current_user)


@fandom_router.post(
    "/invites/join",
    response_model=FandomJoinResponse,
    summary="Gia nhập Fandom bằng mã mời",
    description="Tiêu thụ một mã mời hợp lệ để gia nhập Fandom (bỏ qua phê duyệt xét tuyển nếu là Fandom riêng tư hoặc cần duyệt).",
    responses={
        400: {"description": "Mã mời đã hết hạn, hết lượt sử dụng hoặc người dùng đã là thành viên"},
        403: {"description": "Người dùng đã bị cấm khỏi Fandom này"},
        404: {"description": "Mã mời không tồn tại hoặc đã bị thu hồi"},
        429: {"description": "Thử mã mời quá nhiều lần (Rate Limit)"},
    },
)
@fandom_router.post(
    "/join-by-invite",
    response_model=FandomJoinResponse,
    summary="Gia nhập Fandom bằng mã mời (alias)",
    description="Alias của /invites/join.",
)
async def join_by_invite(
    data: FandomJoinByInviteRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    """Consumes an invite code to join a fandom."""
    return await FandomService.join_by_invite(db, data.code, current_user, redis=redis)


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
@fandom_router.get(
    "/{slug}",
    response_model=FandomDetail,
    summary="Xem hồ sơ chi tiết của một Fandom công khai (alias)",
    include_in_schema=False,
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


@fandom_router.post(
    "/{identifier}/join",
    response_model=FandomJoinResponse,
    summary="Tham gia hoặc gửi đơn xin gia nhập Fandom",
    description="""
    Thực hiện tham gia hoặc nộp đơn xin gia nhập Fandom:
    - Nếu Fandom chế độ **OPEN**: Gia nhập tức thời thành viên `ACTIVE`.
    - Nếu Fandom chế độ **APPROVAL**: Tạo đơn xét tuyển `PENDING` chờ Chủ Fandom duyệt.
    - Áp dụng Rate Limit: Tối đa 5 thao tác / phút trên mỗi Fandom.
    """,
    responses={
        400: {"description": "Người dùng là Chủ sở hữu hoặc đã là thành viên"},
        403: {"description": "Fandom riêng tư hoặc người dùng đã bị cấm khỏi Fandom"},
        404: {"description": "Không tìm thấy Fandom"},
        409: {"description": "Đã có yêu cầu gia nhập đang chờ duyệt"},
        429: {"description": "Thao tác quá nhanh (Rate Limit)"},
    },
)
async def join_fandom(
    identifier: str,
    answers_payload: dict | None = Body(None),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    """Joins an OPEN fandom or stages an approval request."""
    return await FandomService.join_fandom(
        db=db,
        identifier=identifier,
        current_user=current_user,
        answers_payload=answers_payload,
        redis=redis,
    )


@fandom_router.delete(
    "/{identifier}/join-requests/me",
    response_model=FandomCancelRequestResponse,
    summary="Hủy yêu cầu tham gia Fandom đang chờ duyệt",
    description="Cho phép người dùng rút lại đơn xin gia nhập đang ở trạng thái PENDING.",
    responses={
        404: {"description": "Không có yêu cầu chờ duyệt nào của người dùng"},
    },
)
@fandom_router.post(
    "/{identifier}/cancel-request",
    response_model=FandomCancelRequestResponse,
    summary="Hủy yêu cầu tham gia Fandom đang chờ duyệt (alias)",
    description="Alias của DELETE /{identifier}/join-requests/me.",
)
async def cancel_join_request(
    identifier: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    """Cancels a pending join request."""
    return await FandomService.cancel_join_request(
        db=db,
        identifier=identifier,
        current_user=current_user,
        redis=redis,
    )


@fandom_router.post(
    "/{identifier}/leave",
    response_model=FandomLeaveResponse,
    summary="Rời khỏi Fandom",
    description="Hủy tư cách thành viên khỏi Fandom. Chủ sở hữu (Owner) không được phép rời Fandom của mình.",
    responses={
        400: {"description": "Chủ sở hữu không thể rời hoặc người dùng không phải thành viên"},
        404: {"description": "Không tìm thấy Fandom"},
    },
)
async def leave_fandom(
    identifier: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    """Leaves a joined fandom."""
    return await FandomService.leave_fandom(
        db=db,
        identifier=identifier,
        current_user=current_user,
        redis=redis,
    )


@fandom_router.post(
    "/{identifier}/invites",
    response_model=FandomInviteOut,
    status_code=status.HTTP_201_CREATED,
    summary="Tạo mã mời tham gia Fandom (Owner/Mod)",
    description="Tạo một mã mời có thể tùy chỉnh số lượt dùng tối đa và thời hạn hiệu lực.",
    responses={
        403: {"description": "Chỉ Chủ sở hữu mới có quyền tạo mã mời"},
        404: {"description": "Không tìm thấy Fandom"},
    },
)
async def create_invite(
    identifier: str,
    data: FandomInviteCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Generates an invite code for a fandom."""
    return await FandomService.create_invite(
        db=db,
        identifier=identifier,
        current_user=current_user,
        data=data,
    )


@fandom_router.get(
    "/{identifier}/join-requests",
    response_model=list[FandomJoinRequestOut],
    summary="Xem danh sách đơn xin gia nhập Fandom (Owner/Mod)",
    description="Trả về danh sách các đơn xét tuyển đang chờ duyệt hoặc đã xử lý.",
    responses={
        403: {"description": "Chỉ Chủ sở hữu mới có quyền xem đơn gia nhập"},
        404: {"description": "Không tìm thấy Fandom"},
    },
)
async def list_join_requests(
    identifier: str,
    status_filter: str = Query("PENDING", description="Bộ lọc trạng thái: PENDING, APPROVED, REJECTED"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Lists join requests for a fandom."""
    return await FandomService.list_join_requests(
        db=db,
        identifier=identifier,
        current_user=current_user,
        status_filter=status_filter,
    )


@fandom_router.post(
    "/{identifier}/join-requests/{request_id}/review",
    response_model=FandomJoinResponse,
    summary="Phê duyệt hoặc từ chối đơn gia nhập (Owner/Mod)",
    description="Phê duyệt (APPROVE) hoặc từ chối (REJECT) một đơn xin gia nhập đang chờ duyệt.",
    responses={
        400: {"description": "Hành động không hợp lệ"},
        403: {"description": "Không có quyền duyệt đơn"},
        404: {"description": "Không tìm thấy đơn gia nhập hoặc Fandom"},
    },
)
async def review_join_request(
    identifier: str,
    request_id: uuid.UUID,
    data: FandomJoinRequestReview,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    """Approves or rejects a join request."""
    return await FandomService.review_join_request(
        db=db,
        identifier=identifier,
        request_id=request_id,
        current_user=current_user,
        action=data.action,
        redis=redis,
    )
