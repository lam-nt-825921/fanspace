"""Fandom Domain Service.

Provides business logic for creating fandom communities, querying the public
directory with accent-insensitive and case-insensitive search (across fandom name,
slug, owner name, and owner ID), multi-criteria sorting, bounded offset pagination,
and Redis Cache-Aside optimization for 10,000 CCU read workloads.
"""

import secrets
import unicodedata
import uuid
from datetime import datetime, timezone, timedelta
import orjson
import redis.asyncio as aioredis
from fastapi import HTTPException, status
from sqlalchemy import String, asc, cast, desc, func, or_, select, delete
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import contains_eager, selectinload

from app.modules.identity.models import User
from app.modules.fandom.models import Fandom, FandomMember, FandomInvite, FandomJoinRequest
from app.modules.rbac.models import Role, MemberRole, PermissionBit
from app.modules.fandom.schemas import (
    FandomCreate,
    FandomDetail,
    FandomSortBy,
    FandomSummary,
    FandomJoinResponse,
    FandomLeaveResponse,
    FandomCancelRequestResponse,
    FandomInviteCreate,
    FandomInviteOut,
    FandomJoinRequestOut,
    MyFandomsResponse,
)
from app.modules.media.service import MediaService

SUMMARY_DESCRIPTION_MAX_LENGTH = 160
FANDOM_LIST_CACHE_TTL_SECONDS = 30
FANDOM_PREVIEW_CACHE_TTL_SECONDS = 120


def normalize_search_text(text: str) -> str:
    """Normalizes search input by lowercasing and stripping Vietnamese diacritics ('đ/Đ' -> 'd').

    Args:
        text (str): Raw search keyword.

    Returns:
        str: Lowercase accent-stripped string.
    """
    replaced = text.replace("đ", "d").replace("Đ", "D").strip().lower()
    decomposed = unicodedata.normalize("NFD", replaced)
    return "".join(ch for ch in decomposed if unicodedata.category(ch) != "Mn")


def truncate_summary_description(description: str | None, max_length: int = SUMMARY_DESCRIPTION_MAX_LENGTH) -> str | None:
    """Truncates a fandom description for lightweight directory summary cards.

    Args:
        description (str | None): Full fandom description text.
        max_length (int): Maximum character count before truncation (default 160).

    Returns:
        str | None: Truncated description with ellipsis if exceeding `max_length`, or None.
    """
    if description is None:
        return None
    cleaned = description.strip()
    if len(cleaned) <= max_length:
        return cleaned
    return f"{cleaned[: max_length - 3].rstrip()}..."


class FandomService:
    """Service providing core fandom community management and discovery operations."""

    @staticmethod
    async def invalidate_fandom_caches(
        redis: aioredis.Redis | None,
        slug: str | None = None,
    ) -> None:
        """Invalidates cached directory pages and specific fandom preview entries in Redis.

        Args:
            redis (aioredis.Redis | None): Active Redis client, if available.
            slug (str | None): Optional fandom slug to invalidate its preview cache.
        """
        if not redis:
            return
        try:
            if slug:
                await redis.delete(f"cache:fandom:preview:{slug.lower()}")
            cursor = 0
            while True:
                cursor, keys = await redis.scan(cursor=cursor, match="cache:fandoms:list:*", count=100)
                if keys:
                    await redis.delete(*keys)
                if cursor == 0:
                    break
        except Exception:
            pass

    @classmethod
    async def create_fandom(
        cls,
        db: AsyncSession,
        owner: User,
        data: FandomCreate,
        redis: aioredis.Redis | None = None,
    ) -> Fandom:
        """Provisions a new fandom community and grants the creator the Owner role.

        Args:
            db (AsyncSession): Active database session.
            owner (User): Authenticated user creating the community.
            data (FandomCreate): Parameters defining the new fandom.
            redis (aioredis.Redis | None): Optional Redis client for cache invalidation.

        Returns:
            Fandom: The newly initialized and committed Fandom database record.

        Raises:
            HTTPException: 400 Bad Request if the slug is already registered or media limits are exceeded.
        """
        clean_slug = data.slug.strip().lower()
        validated_illustrations = MediaService.validate_illustration_urls(data.illustration_urls)

        query = select(Fandom).where(Fandom.slug == clean_slug)
        result = await db.execute(query)
        if result.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Đường dẫn (slug) '@{clean_slug}' đã tồn tại, vui lòng chọn slug khác.",
            )

        fandom = Fandom(
            name=data.name.strip(),
            slug=clean_slug,
            description=data.description.strip() if data.description else None,
            category=data.category.strip(),
            avatar_url=data.avatar_url,
            banner_url=data.banner_url,
            illustration_urls=validated_illustrations,
            is_public=data.is_public,
            admission_mode=data.admission_mode,
            rules_tos=data.rules_tos.strip() if data.rules_tos else None,
            owner_id=owner.id,
            member_count=1,
        )
        db.add(fandom)
        await db.flush()

        owner_role = Role(
            fandom_id=fandom.id,
            name="Chủ Fandom (Owner)",
            color_hex="#E91E63",
            priority=100,
            permissions_bitmask=PermissionBit.ADMINISTRATOR,
            is_preset_mod=False,
            is_membership_tier=False,
        )
        db.add(owner_role)
        await db.flush()

        member = FandomMember(
            fandom_id=fandom.id,
            user_id=owner.id,
            status="ACTIVE",
        )
        db.add(member)
        await db.flush()

        member_role = MemberRole(
            fandom_id=fandom.id,
            user_id=owner.id,
            role_id=owner_role.id,
            assigned_by=owner.id,
        )
        db.add(member_role)

        await db.commit()
        await db.refresh(fandom)
        await cls.invalidate_fandom_caches(redis, slug=clean_slug)
        return fandom

    @staticmethod
    async def list_public(
        db: AsyncSession,
        search: str | None = None,
        category: str | None = None,
        sort_by: FandomSortBy = FandomSortBy.POPULAR,
        limit: int = 20,
        offset: int = 0,
        redis: aioredis.Redis | None = None,
    ) -> list[FandomSummary]:
        """Queries the public fandom directory with search, category filter, sorting, and Redis caching.

        Supports case-insensitive and accent-insensitive search across:
        - Fandom `name` and `slug`
        - Owner `display_name` and `username`
        - Owner `id` (`owner_id` exact or partial UUID match)

        Args:
            db (AsyncSession): Active database session.
            search (str | None): Optional search keyword.
            category (str | None): Optional category filter.
            sort_by (FandomSortBy): Sorting strategy ('popular', 'newest', 'name_asc').
            limit (int): Page size (1 - 50, default 20).
            offset (int): Pagination offset (0 - 1000, default 0).
            redis (aioredis.Redis | None): Optional Redis client for Cache-Aside acceleration.

        Returns:
            list[FandomSummary]: List of lightweight fandom summary objects.
        """
        clean_search = search.strip() if search and search.strip() else None
        clean_category = (
            category.strip()
            if category and category.strip() and category.strip().lower() not in ("all", "tất cả")
            else None
        )

        # 1. Check Redis Cache for non-keyword browsing pages (absorbs ~90% of 10,000 CCU read traffic)
        cache_key: str | None = None
        if redis and not clean_search:
            cat_token = (clean_category or "all").lower()
            cache_key = f"cache:fandoms:list:{cat_token}:{sort_by.value}:{limit}:{offset}"
            try:
                cached_raw = await redis.get(cache_key)
                if cached_raw:
                    items = orjson.loads(cached_raw)
                    return [FandomSummary(**item) for item in items]
            except Exception:
                pass

        # 2. Build indexed SQL query joining owner profile
        query = (
            select(Fandom)
            .join(Fandom.owner)
            .options(contains_eager(Fandom.owner))
            .where(Fandom.is_public == True)
        )

        if clean_category:
            query = query.where(Fandom.category == clean_category)

        if clean_search:
            norm_kw = f"%{normalize_search_text(clean_search)}%"
            raw_kw = f"%{clean_search.lower()}%"

            search_conditions = [
                func.f_unaccent(func.lower(Fandom.name)).like(norm_kw),
                func.lower(Fandom.slug).like(norm_kw),
                func.f_unaccent(func.lower(User.display_name)).like(norm_kw),
                func.lower(User.username).like(norm_kw),
                cast(Fandom.owner_id, String).ilike(raw_kw),
            ]
            try:
                parsed_owner_uuid = uuid.UUID(clean_search)
                search_conditions.append(Fandom.owner_id == parsed_owner_uuid)
            except ValueError:
                pass

            query = query.where(or_(*search_conditions))

        # 3. Apply sorting strategy
        if sort_by == FandomSortBy.NEWEST:
            query = query.order_by(desc(Fandom.created_at), desc(Fandom.id))
        elif sort_by == FandomSortBy.NAME_ASC:
            query = query.order_by(asc(Fandom.name), asc(Fandom.id))
        else:
            query = query.order_by(desc(Fandom.member_count), desc(Fandom.created_at), desc(Fandom.id))

        query = query.offset(offset).limit(limit)
        result = await db.execute(query)
        fandoms = result.scalars().all()

        summaries = [
            FandomSummary(
                id=f.id,
                name=f.name,
                slug=f.slug,
                description=truncate_summary_description(f.description),
                category=f.category,
                avatar_url=f.avatar_url,
                banner_url=f.banner_url,
                admission_mode=f.admission_mode,
                member_count=f.member_count,
                owner_id=f.owner_id,
                owner_name=f.owner.display_name if f.owner else "Ẩn danh",
                created_at=f.created_at,
            )
            for f in fandoms
        ]

        # 4. Populate Redis Cache for common directory pages
        if redis and cache_key:
            try:
                payload = [s.model_dump(mode="json") for s in summaries]
                await redis.set(
                    cache_key,
                    orjson.dumps(payload).decode("utf-8"),
                    ex=FANDOM_LIST_CACHE_TTL_SECONDS,
                )
            except Exception:
                pass

        return summaries

    @staticmethod
    async def get_preview(
        db: AsyncSession,
        slug: str,
        current_user: User | None = None,
        redis: aioredis.Redis | None = None,
    ) -> FandomDetail:
        """Retrieves complete profile metadata for a fandom community by slug.

        Uses Redis Cache-Aside (`cache:fandom:preview:{slug}`) for the shared public profile
        fields and performs at most one indexed point lookup on `fandom_members` to compute
        contextual `is_owner` and `is_member` flags when `current_user` is authenticated.

        Args:
            db (AsyncSession): Active database session.
            slug (str): Unique URL slug of the fandom space.
            current_user (User | None): Optional authenticated user viewing the profile.
            redis (aioredis.Redis | None): Optional Redis client for caching.

        Returns:
            FandomDetail: Complete fandom profile metadata.

        Raises:
            HTTPException: 404 Not Found if no public fandom matches the slug (unless viewed by its owner).
        """
        clean_slug = slug.strip().lower()
        cache_key = f"cache:fandom:preview:{clean_slug}"
        base_profile: dict | None = None

        # 1. Attempt to read shared public profile from Redis Cache
        if redis:
            try:
                cached_raw = await redis.get(cache_key)
                if cached_raw:
                    base_profile = orjson.loads(cached_raw)
            except Exception:
                base_profile = None

        # 2. On cache miss, query PostgreSQL
        if base_profile is None:
            query = (
                select(Fandom)
                .where(Fandom.slug == clean_slug)
                .options(selectinload(Fandom.owner))
            )
            result = await db.execute(query)
            fandom = result.scalar_one_or_none()

            if not fandom:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=f"Không tìm thấy không gian Fandom '@{clean_slug}'.",
                )

            if not fandom.is_public and (not current_user or fandom.owner_id != current_user.id):
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=f"Không tìm thấy không gian Fandom '@{clean_slug}'.",
                )

            base_profile = {
                "id": str(fandom.id),
                "name": fandom.name,
                "slug": fandom.slug,
                "description": fandom.description,
                "category": fandom.category,
                "avatar_url": fandom.avatar_url,
                "banner_url": fandom.banner_url,
                "illustration_urls": list(fandom.illustration_urls) if fandom.illustration_urls else [],
                "is_public": fandom.is_public,
                "admission_mode": fandom.admission_mode,
                "rules_tos": fandom.rules_tos,
                "member_count": fandom.member_count,
                "owner_id": str(fandom.owner_id),
                "owner_name": fandom.owner.display_name if fandom.owner else "Ẩn danh",
                "owner_username": fandom.owner.username if fandom.owner else None,
                "owner_avatar_url": fandom.owner.avatar_url if fandom.owner else None,
                "created_at": fandom.created_at.isoformat(),
            }

            # Only cache public fandom profiles in shared Redis cache
            if redis and fandom.is_public:
                try:
                    await redis.set(
                        cache_key,
                        orjson.dumps(base_profile).decode("utf-8"),
                        ex=FANDOM_PREVIEW_CACHE_TTL_SECONDS,
                    )
                except Exception:
                    pass

        # 3. Compute user-specific contextual flags (is_owner, is_member, is_pending_request)
        fandom_uuid = uuid.UUID(str(base_profile["id"]))
        owner_uuid = uuid.UUID(str(base_profile["owner_id"]))
        is_owner = False
        is_member = False
        is_pending_request = False

        if current_user:
            is_owner = owner_uuid == current_user.id
            if is_owner:
                is_member = True
            else:
                mem_query = (
                    select(FandomMember.id)
                    .where(
                        FandomMember.fandom_id == fandom_uuid,
                        FandomMember.user_id == current_user.id,
                        FandomMember.status == "ACTIVE",
                    )
                    .limit(1)
                )
                mem_result = await db.execute(mem_query)
                is_member = mem_result.scalar_one_or_none() is not None

                if not is_member:
                    req_query = (
                        select(FandomJoinRequest.id)
                        .where(
                            FandomJoinRequest.fandom_id == fandom_uuid,
                            FandomJoinRequest.user_id == current_user.id,
                            FandomJoinRequest.status == "PENDING",
                        )
                        .limit(1)
                    )
                    req_result = await db.execute(req_query)
                    is_pending_request = req_result.scalar_one_or_none() is not None

        return FandomDetail(
            **base_profile,
            is_owner=is_owner,
            is_member=is_member,
            is_pending_request=is_pending_request,
        )

    @staticmethod
    async def _resolve_fandom(db: AsyncSession, identifier: str) -> Fandom:
        """Finds a fandom by either UUID or unique slug."""
        clean_identifier = identifier.strip()
        fandom_uuid = None
        try:
            fandom_uuid = uuid.UUID(clean_identifier)
        except ValueError:
            pass

        if fandom_uuid:
            query = select(Fandom).where(Fandom.id == fandom_uuid)
        else:
            query = select(Fandom).where(func.lower(Fandom.slug) == clean_identifier.lower())

        result = await db.execute(query)
        fandom = result.scalar_one_or_none()
        if not fandom:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Không tìm thấy không gian Fandom '{identifier}'.",
            )
        return fandom

    @staticmethod
    async def _check_action_rate_limit(redis: aioredis.Redis | None, user_id: uuid.UUID, fandom_id: uuid.UUID) -> None:
        """Enforces sliding-window rate limit: max 5 join/leave/cancel actions per user per fandom in 60s."""
        if not redis:
            return
        rate_key = f"ratelimit:fandom_action:{user_id}:{fandom_id}"
        try:
            current_count = await redis.incr(rate_key)
            if current_count == 1:
                await redis.expire(rate_key, 60)
            if current_count > 5:
                ttl = await redis.ttl(rate_key)
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail=f"Bạn thao tác quá nhanh. Vui lòng thử lại sau {max(ttl, 1)} giây.",
                )
        except HTTPException:
            raise
        except Exception:
            pass

    @staticmethod
    async def _invalidate_fandom_membership_caches(
        redis: aioredis.Redis | None,
        fandom: Fandom,
        user_id: uuid.UUID | None = None,
    ) -> None:
        """Evicts Redis caches associated with fandom preview, user cards, and directory listings."""
        if not redis:
            return
        try:
            await redis.delete(f"cache:fandom:preview:{fandom.slug.lower()}")
            if user_id:
                await redis.delete(f"cache:user:card:{user_id}")
                await redis.delete(f"cache:user:fandoms:{user_id}")
        except Exception:
            pass

    @classmethod
    async def join_fandom(
        cls,
        db: AsyncSession,
        identifier: str,
        current_user: User,
        answers_payload: dict | None = None,
        redis: aioredis.Redis | None = None,
    ) -> FandomJoinResponse:
        """Joins an OPEN fandom or submits a join request for an APPROVAL fandom."""
        fandom = await cls._resolve_fandom(db, identifier)
        await cls._check_action_rate_limit(redis, current_user.id, fandom.id)

        # 1. Owner cannot join own fandom
        if fandom.owner_id == current_user.id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Bạn là Chủ sở hữu (Owner) của Fandom này.",
            )

        # 2. Check existing membership status
        mem_query = select(FandomMember).where(
            FandomMember.fandom_id == fandom.id,
            FandomMember.user_id == current_user.id,
        )
        mem_res = await db.execute(mem_query)
        existing_member = mem_res.scalar_one_or_none()

        if existing_member:
            if existing_member.status == "BANNED":
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Bạn đã bị cấm khỏi Fandom này và không thể tham gia.",
                )
            if existing_member.status == "ACTIVE":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Bạn đã là thành viên của Fandom này rồi.",
                )

        # 3. Private fandom requires invite code
        if not fandom.is_public:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Fandom này là riêng tư. Bạn cần có mã mời hợp lệ để tham gia.",
            )

        # 4. Handle admission mode
        if fandom.admission_mode == "OPEN":
            if existing_member:
                existing_member.status = "ACTIVE"
                existing_member.joined_at = datetime.now(timezone.utc)
            else:
                new_member = FandomMember(
                    fandom_id=fandom.id,
                    user_id=current_user.id,
                    status="ACTIVE",
                )
                db.add(new_member)

            fandom.member_count = fandom.member_count + 1

            # Delete any previous pending request if it existed
            await db.execute(
                delete(FandomJoinRequest).where(
                    FandomJoinRequest.fandom_id == fandom.id,
                    FandomJoinRequest.user_id == current_user.id,
                )
            )

            await db.commit()
            await cls._invalidate_fandom_membership_caches(redis, fandom, current_user.id)

            return FandomJoinResponse(
                success=True,
                message=f"Chúc mừng bạn đã gia nhập Fandom '{fandom.name}' thành công!",
                status="JOINED",
                fandom_id=fandom.id,
                slug=fandom.slug,
            )

        # APPROVAL mode: check for duplicate pending request
        req_query = select(FandomJoinRequest).where(
            FandomJoinRequest.fandom_id == fandom.id,
            FandomJoinRequest.user_id == current_user.id,
            FandomJoinRequest.status == "PENDING",
        )
        existing_req = (await db.execute(req_query)).scalar_one_or_none()
        if existing_req:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Bạn đã gửi yêu cầu gia nhập và đang chờ Chủ Fandom phê duyệt.",
            )

        join_request = FandomJoinRequest(
            fandom_id=fandom.id,
            user_id=current_user.id,
            status="PENDING",
            answers_payload=answers_payload,
        )
        db.add(join_request)
        await db.commit()
        await cls._invalidate_fandom_membership_caches(redis, fandom, current_user.id)

        return FandomJoinResponse(
            success=True,
            message=f"Đã gửi yêu cầu gia nhập Fandom '{fandom.name}'. Vui lòng chờ Chủ Fandom phê duyệt.",
            status="REQUEST_SUBMITTED",
            fandom_id=fandom.id,
            slug=fandom.slug,
        )

    @classmethod
    async def cancel_join_request(
        cls,
        db: AsyncSession,
        identifier: str,
        current_user: User,
        redis: aioredis.Redis | None = None,
    ) -> FandomCancelRequestResponse:
        """Cancels a pending join request submitted by the current user."""
        fandom = await cls._resolve_fandom(db, identifier)
        await cls._check_action_rate_limit(redis, current_user.id, fandom.id)

        req_query = select(FandomJoinRequest).where(
            FandomJoinRequest.fandom_id == fandom.id,
            FandomJoinRequest.user_id == current_user.id,
            FandomJoinRequest.status == "PENDING",
        )
        join_request = (await db.execute(req_query)).scalar_one_or_none()
        if not join_request:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Không tìm thấy yêu cầu gia nhập đang chờ duyệt nào của bạn.",
            )

        await db.delete(join_request)
        await db.commit()
        await cls._invalidate_fandom_membership_caches(redis, fandom, current_user.id)

        return FandomCancelRequestResponse(
            success=True,
            message=f"Đã hủy yêu cầu tham gia Fandom '{fandom.name}' thành công.",
            fandom_id=fandom.id,
        )

    @classmethod
    async def leave_fandom(
        cls,
        db: AsyncSession,
        identifier: str,
        current_user: User,
        redis: aioredis.Redis | None = None,
    ) -> FandomLeaveResponse:
        """Leaves a joined fandom. Fandom owners are prevented from leaving without transferring ownership."""
        fandom = await cls._resolve_fandom(db, identifier)
        await cls._check_action_rate_limit(redis, current_user.id, fandom.id)

        if fandom.owner_id == current_user.id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Chủ sở hữu (Owner) không thể rời Fandom của chính mình.",
            )

        mem_query = select(FandomMember).where(
            FandomMember.fandom_id == fandom.id,
            FandomMember.user_id == current_user.id,
            FandomMember.status == "ACTIVE",
        )
        membership = (await db.execute(mem_query)).scalar_one_or_none()
        if not membership:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Bạn hiện không phải là thành viên hoạt động của Fandom này.",
            )

        await db.delete(membership)
        fandom.member_count = max(1, fandom.member_count - 1)
        await db.commit()
        await cls._invalidate_fandom_membership_caches(redis, fandom, current_user.id)

        return FandomLeaveResponse(
            success=True,
            message=f"Bạn đã rời khỏi Fandom '{fandom.name}' thành công.",
            fandom_id=fandom.id,
        )

    @classmethod
    async def create_invite(
        cls,
        db: AsyncSession,
        identifier: str,
        current_user: User,
        data: FandomInviteCreate,
    ) -> FandomInviteOut:
        """Generates a secure invite code for a fandom (restricted to Owner/Moderators)."""
        fandom = await cls._resolve_fandom(db, identifier)

        # Authorization: only owner or system admin can create invites
        if fandom.owner_id != current_user.id and current_user.system_role not in ("SYSTEM_ADMIN", "SYSTEM_MODERATOR"):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Chỉ Chủ sở hữu Fandom mới có quyền tạo mã mời.",
            )

        code = secrets.token_hex(4).upper()
        expires_at = None
        if data.expires_in_hours:
            expires_at = datetime.now(timezone.utc) + timedelta(hours=data.expires_in_hours)

        invite = FandomInvite(
            fandom_id=fandom.id,
            code=code,
            max_uses=data.max_uses,
            uses_count=0,
            expires_at=expires_at,
            created_by=current_user.id,
        )
        db.add(invite)
        await db.commit()
        await db.refresh(invite)

        return FandomInviteOut(
            code=invite.code,
            fandom_id=fandom.id,
            fandom_name=fandom.name,
            fandom_slug=fandom.slug,
            max_uses=invite.max_uses,
            uses_count=invite.uses_count,
            expires_at=invite.expires_at,
            created_at=invite.created_at,
        )

    @classmethod
    async def join_by_invite(
        cls,
        db: AsyncSession,
        code: str,
        current_user: User,
        redis: aioredis.Redis | None = None,
    ) -> FandomJoinResponse:
        """Consumes a valid invite code to immediately join a fandom, bypassing approval."""
        clean_code = code.strip().upper()

        # Brute-force rate limit on invite codes
        if redis:
            brute_key = f"ratelimit:invite_bruteforce:{current_user.id}"
            try:
                attempts = await redis.incr(brute_key)
                if attempts == 1:
                    await redis.expire(brute_key, 900)  # 15 minutes window
                if attempts > 10:
                    raise HTTPException(
                        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                        detail="Bạn đã thử mã mời quá nhiều lần. Vui lòng thử lại sau 15 phút.",
                    )
            except HTTPException:
                raise
            except Exception:
                pass

        inv_query = (
            select(FandomInvite)
            .options(selectinload(FandomInvite.fandom))
            .where(FandomInvite.code == clean_code)
        )
        invite = (await db.execute(inv_query)).scalar_one_or_none()
        if not invite:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Mã mời không tồn tại hoặc đã bị thu hồi.",
            )

        now = datetime.now(timezone.utc)
        if invite.expires_at and invite.expires_at < now:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Mã mời đã hết thời hạn hiệu lực.",
            )

        if invite.max_uses and invite.uses_count >= invite.max_uses:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Mã mời đã đạt tối đa số lượt sử dụng.",
            )

        fandom = invite.fandom
        if fandom.owner_id == current_user.id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Bạn là Chủ sở hữu của Fandom này.",
            )

        mem_query = select(FandomMember).where(
            FandomMember.fandom_id == fandom.id,
            FandomMember.user_id == current_user.id,
        )
        existing_mem = (await db.execute(mem_query)).scalar_one_or_none()

        if existing_mem:
            if existing_mem.status == "BANNED":
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Bạn đã bị cấm khỏi Fandom này.",
                )
            if existing_mem.status == "ACTIVE":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Bạn đã là thành viên của Fandom này rồi.",
                )
            existing_mem.status = "ACTIVE"
            existing_mem.joined_at = now
        else:
            db.add(FandomMember(fandom_id=fandom.id, user_id=current_user.id, status="ACTIVE"))

        # Increment usages & member count atomically
        invite.uses_count = invite.uses_count + 1
        fandom.member_count = fandom.member_count + 1

        # Delete any pending requests
        await db.execute(
            delete(FandomJoinRequest).where(
                FandomJoinRequest.fandom_id == fandom.id,
                FandomJoinRequest.user_id == current_user.id,
            )
        )

        await db.commit()
        await cls._invalidate_fandom_membership_caches(redis, fandom, current_user.id)

        return FandomJoinResponse(
            success=True,
            message=f"Đã gia nhập Fandom '{fandom.name}' thành công qua mã mời!",
            status="JOINED",
            fandom_id=fandom.id,
            slug=fandom.slug,
        )

    @classmethod
    async def list_join_requests(
        cls,
        db: AsyncSession,
        identifier: str,
        current_user: User,
        status_filter: str = "PENDING",
    ) -> list[FandomJoinRequestOut]:
        """Lists join requests for a fandom (accessible only to Owner/Admins)."""
        fandom = await cls._resolve_fandom(db, identifier)
        if fandom.owner_id != current_user.id and current_user.system_role not in ("SYSTEM_ADMIN", "SYSTEM_MODERATOR"):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Chỉ Chủ sở hữu Fandom mới có quyền xem danh sách đơn gia nhập.",
            )

        query = (
            select(FandomJoinRequest)
            .options(selectinload(FandomJoinRequest.user), selectinload(FandomJoinRequest.fandom))
            .where(
                FandomJoinRequest.fandom_id == fandom.id,
                FandomJoinRequest.status == status_filter.upper(),
            )
            .order_by(desc(FandomJoinRequest.created_at))
        )
        results = (await db.execute(query)).scalars().all()

        return [
            FandomJoinRequestOut(
                id=req.id,
                fandom_id=fandom.id,
                fandom_name=fandom.name,
                fandom_slug=fandom.slug,
                fandom_avatar_url=fandom.avatar_url,
                user_id=req.user_id,
                username=req.user.username if req.user else "user",
                display_name=req.user.display_name if req.user else "Người dùng",
                avatar_url=req.user.avatar_url if req.user else None,
                status=req.status,
                answers_payload=req.answers_payload,
                created_at=req.created_at,
            )
            for req in results
        ]

    @classmethod
    async def review_join_request(
        cls,
        db: AsyncSession,
        identifier: str,
        request_id: uuid.UUID,
        current_user: User,
        action: str,
        redis: aioredis.Redis | None = None,
    ) -> FandomJoinResponse:
        """Approves or rejects a pending join request."""
        fandom = await cls._resolve_fandom(db, identifier)
        if fandom.owner_id != current_user.id and current_user.system_role not in ("SYSTEM_ADMIN", "SYSTEM_MODERATOR"):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Chỉ Chủ sở hữu Fandom mới có quyền duyệt đơn gia nhập.",
            )

        req_query = select(FandomJoinRequest).where(
            FandomJoinRequest.id == request_id,
            FandomJoinRequest.fandom_id == fandom.id,
        )
        join_request = (await db.execute(req_query)).scalar_one_or_none()
        if not join_request or join_request.status != "PENDING":
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Yêu cầu gia nhập không tồn tại hoặc đã được xử lý từ trước.",
            )

        now = datetime.now(timezone.utc)
        clean_action = action.strip().upper()

        if clean_action == "APPROVE":
            join_request.status = "APPROVED"
            join_request.reviewed_by = current_user.id
            join_request.reviewed_at = now

            # Add to FandomMember
            mem_query = select(FandomMember).where(
                FandomMember.fandom_id == fandom.id,
                FandomMember.user_id == join_request.user_id,
            )
            existing_mem = (await db.execute(mem_query)).scalar_one_or_none()
            if existing_mem:
                existing_mem.status = "ACTIVE"
                existing_mem.joined_at = now
            else:
                db.add(FandomMember(fandom_id=fandom.id, user_id=join_request.user_id, status="ACTIVE"))

            fandom.member_count = fandom.member_count + 1
            await db.commit()
            await cls._invalidate_fandom_membership_caches(redis, fandom, join_request.user_id)

            return FandomJoinResponse(
                success=True,
                message="Đã phê duyệt yêu cầu gia nhập thành công.",
                status="JOINED",
                fandom_id=fandom.id,
                slug=fandom.slug,
            )

        elif clean_action == "REJECT":
            join_request.status = "REJECTED"
            join_request.reviewed_by = current_user.id
            join_request.reviewed_at = now
            await db.commit()
            await cls._invalidate_fandom_membership_caches(redis, fandom, join_request.user_id)

            return FandomJoinResponse(
                success=True,
                message="Đã từ chối yêu cầu gia nhập.",
                status="REJECTED",
                fandom_id=fandom.id,
                slug=fandom.slug,
            )
        else:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Hành động không hợp lệ. Chỉ chấp nhận 'APPROVE' hoặc 'REJECT'.",
            )

    @classmethod
    async def get_my_fandoms(cls, db: AsyncSession, current_user: User) -> MyFandomsResponse:
        """Retrieves joined fandoms, owned fandoms, and active pending join requests for the user."""
        # 1. Joined Fandoms (ACTIVE member, not owner)
        joined_query = (
            select(Fandom)
            .join(FandomMember, Fandom.id == FandomMember.fandom_id)
            .options(selectinload(Fandom.owner))
            .where(
                FandomMember.user_id == current_user.id,
                FandomMember.status == "ACTIVE",
                Fandom.owner_id != current_user.id,
            )
            .order_by(desc(Fandom.created_at))
        )
        joined_fandoms = (await db.execute(joined_query)).scalars().all()

        joined_summaries = [
            FandomSummary(
                id=f.id,
                name=f.name,
                slug=f.slug,
                description=truncate_summary_description(f.description),
                category=f.category,
                avatar_url=f.avatar_url,
                banner_url=f.banner_url,
                admission_mode=f.admission_mode,
                member_count=f.member_count,
                owner_id=f.owner_id,
                owner_name=f.owner.display_name if f.owner else "Ẩn danh",
                created_at=f.created_at,
            )
            for f in joined_fandoms
        ]

        # 2. Managed / Owned Fandoms
        managed_query = (
            select(Fandom)
            .options(selectinload(Fandom.owner))
            .where(Fandom.owner_id == current_user.id)
            .order_by(desc(Fandom.created_at))
        )
        managed_fandoms = (await db.execute(managed_query)).scalars().all()

        managed_summaries = [
            FandomSummary(
                id=f.id,
                name=f.name,
                slug=f.slug,
                description=truncate_summary_description(f.description),
                category=f.category,
                avatar_url=f.avatar_url,
                banner_url=f.banner_url,
                admission_mode=f.admission_mode,
                member_count=f.member_count,
                owner_id=f.owner_id,
                owner_name=f.owner.display_name if f.owner else "Ẩn danh",
                created_at=f.created_at,
            )
            for f in managed_fandoms
        ]

        # 3. Pending Requests
        pending_query = (
            select(FandomJoinRequest)
            .options(selectinload(FandomJoinRequest.fandom))
            .where(
                FandomJoinRequest.user_id == current_user.id,
                FandomJoinRequest.status == "PENDING",
            )
            .order_by(desc(FandomJoinRequest.created_at))
        )
        pending_reqs = (await db.execute(pending_query)).scalars().all()

        pending_summaries = [
            FandomJoinRequestOut(
                id=r.id,
                fandom_id=r.fandom_id,
                fandom_name=r.fandom.name if r.fandom else "",
                fandom_slug=r.fandom.slug if r.fandom else "",
                fandom_avatar_url=r.fandom.avatar_url if r.fandom else None,
                user_id=current_user.id,
                username=current_user.username,
                display_name=current_user.display_name,
                avatar_url=current_user.avatar_url,
                status=r.status,
                answers_payload=r.answers_payload,
                created_at=r.created_at,
            )
            for r in pending_reqs
        ]

        return MyFandomsResponse(
            joined=joined_summaries,
            managed=managed_summaries,
            pending_requests=pending_summaries,
        )
