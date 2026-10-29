"""Fandom Domain Service.

Provides business logic for creating fandom communities, querying the public
directory with accent-insensitive and case-insensitive search (across fandom name,
slug, owner name, and owner ID), multi-criteria sorting, bounded offset pagination,
and Redis Cache-Aside optimization for 10,000 CCU read workloads.
"""

import unicodedata
import uuid
import orjson
import redis.asyncio as aioredis
from fastapi import HTTPException, status
from sqlalchemy import String, asc, cast, desc, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import contains_eager, selectinload

from app.modules.identity.models import User
from app.modules.fandom.models import Fandom, FandomMember
from app.modules.rbac.models import Role, MemberRole, PermissionBit
from app.modules.fandom.schemas import (
    FandomCreate,
    FandomDetail,
    FandomSortBy,
    FandomSummary,
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

        # 3. Compute user-specific contextual flags (is_owner, is_member)
        fandom_uuid = uuid.UUID(str(base_profile["id"]))
        owner_uuid = uuid.UUID(str(base_profile["owner_id"]))
        is_owner = False
        is_member = False

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

        return FandomDetail(
            **base_profile,
            is_owner=is_owner,
            is_member=is_member,
        )
