"""Fandom Domain Service.

This module provides business logic for creating new fandom spaces, setting up
initial creator roles and permissions, querying the public directory, and generating
preview summaries.
"""

import uuid
from datetime import datetime
from fastapi import HTTPException, status
from sqlalchemy import select, or_, desc
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.modules.identity.models import User
from app.modules.fandom.models import Fandom, FandomMember
from app.modules.rbac.models import Role, MemberRole, PermissionBit
from app.modules.fandom.schemas import FandomCreate, FandomSummary, FandomDetail


class FandomService:
    """Service providing core fandom community management operations."""

    @staticmethod
    async def create_fandom(db: AsyncSession, owner: User, data: FandomCreate) -> Fandom:
        """Provisions a new fandom community and grants the creator supreme Owner role.

        Validates slug uniqueness, creates the Fandom entity, provisions an Owner role
        with full `ADMINISTRATOR` bitmask permissions, and enrolls the creator as an
        ACTIVE member.

        Args:
            db (AsyncSession): Active database session.
            owner (User): Authenticated user creating the community.
            data (FandomCreate): Parameters defining the new fandom.

        Returns:
            Fandom: The newly initialized and committed Fandom database record.

        Raises:
            HTTPException: 400 Bad Request if the slug is already registered.
        """
        # Check slug uniqueness
        query = select(Fandom).where(Fandom.slug == data.slug.lower())
        result = await db.execute(query)
        if result.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Đường dẫn (slug) '@{data.slug}' đã tồn tại, vui lòng chọn slug khác.",
            )

        # 1. Create Fandom
        fandom = Fandom(
            name=data.name,
            slug=data.slug.lower(),
            description=data.description,
            category=data.category,
            avatar_url=data.avatar_url,
            banner_url=data.banner_url,
            admission_mode=data.admission_mode,
            rules_tos=data.rules_tos,
            owner_id=owner.id,
            member_count=1,
        )
        db.add(fandom)
        await db.flush()

        # 2. Create Owner Role (Full Admin Bitmask)
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

        # 3. Add Owner as FandomMember
        member = FandomMember(
            fandom_id=fandom.id,
            user_id=owner.id,
            status="ACTIVE",
        )
        db.add(member)
        await db.flush()

        # 4. Assign Owner Role to Owner User
        member_role = MemberRole(
            fandom_id=fandom.id,
            user_id=owner.id,
            role_id=owner_role.id,
            assigned_by=owner.id,
        )
        db.add(member_role)

        await db.commit()
        await db.refresh(fandom)
        return fandom

    @staticmethod
    async def list_public(
        db: AsyncSession,
        search: str | None = None,
        category: str | None = None,
        limit: int = 20,
    ) -> list[FandomSummary]:
        """Queries the public fandom directory filtered by keywords and category.

        Orders communities primarily by member count descending to surface the most
        active spaces first.

        Args:
            db (AsyncSession): Active database session.
            search (str | None, optional): Optional keyword to match against name, slug, or description.
            category (str | None, optional): Optional category filter.
            limit (int, optional): Maximum number of results to return (1-100, default 20).

        Returns:
            list[FandomSummary]: List of summary objects for public listing.
        """
        query = select(Fandom).options(selectinload(Fandom.owner))

        if category and category.lower() != "all" and category.lower() != "tất cả":
            query = query.where(Fandom.category == category)

        if search and search.strip():
            kw = f"%{search.strip().lower()}%"
            query = query.where(
                or_(
                    Fandom.name.ilike(kw),
                    Fandom.slug.ilike(kw),
                    Fandom.description.ilike(kw),
                )
            )

        query = query.order_by(desc(Fandom.member_count), desc(Fandom.created_at)).limit(limit)
        result = await db.execute(query)
        fandoms = result.scalars().all()

        return [
            FandomSummary(
                id=f.id,
                name=f.name,
                slug=f.slug,
                description=f.description,
                category=f.category,
                avatar_url=f.avatar_url,
                banner_url=f.banner_url,
                member_count=f.member_count,
                owner_name=f.owner.display_name if f.owner else "Ẩn danh",
                created_at=f.created_at,
            )
            for f in fandoms
        ]

    @staticmethod
    async def get_preview(
        db: AsyncSession,
        slug: str,
        current_user: User | None = None,
    ) -> FandomDetail:
        """Retrieves detailed preview metadata for a fandom community by slug.

        Calculates `is_owner` and `is_member` contextual flags if a user is authenticated.

        Args:
            db (AsyncSession): Active database session.
            slug (str): Unique URL slug of the fandom space.
            current_user (User | None, optional): Currently logged-in user, or None if unauthenticated.

        Returns:
            FandomDetail: Complete preview details.

        Raises:
            HTTPException: 404 Not Found if no fandom matches the provided slug.
        """
        query = select(Fandom).where(Fandom.slug == slug.lower()).options(selectinload(Fandom.owner))
        result = await db.execute(query)
        fandom = result.scalar_one_or_none()

        if not fandom:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Không tìm thấy không gian Fandom '@{slug}'.",
            )

        is_owner = False
        is_member = False

        if current_user:
            is_owner = fandom.owner_id == current_user.id
            mem_query = select(FandomMember).where(
                FandomMember.fandom_id == fandom.id,
                FandomMember.user_id == current_user.id,
                FandomMember.status == "ACTIVE",
            )
            mem_result = await db.execute(mem_query)
            is_member = mem_result.scalar_one_or_none() is not None

        return FandomDetail(
            id=fandom.id,
            name=fandom.name,
            slug=fandom.slug,
            description=fandom.description,
            category=fandom.category,
            avatar_url=fandom.avatar_url,
            banner_url=fandom.banner_url,
            admission_mode=fandom.admission_mode,
            rules_tos=fandom.rules_tos,
            member_count=fandom.member_count,
            owner_id=fandom.owner_id,
            owner_name=fandom.owner.display_name if fandom.owner else "Ẩn danh",
            is_owner=is_owner,
            is_member=is_member,
            created_at=fandom.created_at,
        )
