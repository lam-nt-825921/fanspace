"""Declarative permission specification, evaluation port, and adapters.

Provides a decoupled authorization layer where business services declare their
expected permissions via `PermissionSpec` (`must_have`, `any_of`, `may_have`)
and evaluate them through the `IPermissionChecker` protocol without coupling to
underlying RBAC storage details.
"""

from __future__ import annotations

import uuid
from abc import ABC, abstractmethod
from collections.abc import Iterable
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import StrEnum
from typing import Protocol

from fastapi import Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db


class Permission(StrEnum):
    """Canonical permission identifiers used across fandom channels and moderation."""

    VIEW_CHANNEL = "VIEW_CHANNEL"
    READ_MESSAGES = "READ_MESSAGES"
    SEND_MESSAGES = "SEND_MESSAGES"
    SEND_ANNOUNCEMENT = "SEND_ANNOUNCEMENT"
    ATTACH_FILES = "ATTACH_FILES"
    EMBED_LINKS = "EMBED_LINKS"
    MODERATE_CHAT = "MODERATE_CHAT"
    BYPASS_SLOWMODE = "BYPASS_SLOWMODE"
    MANAGE_CHANNELS = "MANAGE_CHANNELS"
    MANAGE_ROLES = "MANAGE_ROLES"
    MUTE_MEMBERS = "MUTE_MEMBERS"
    KICK_MEMBERS = "KICK_MEMBERS"
    BAN_MEMBERS = "BAN_MEMBERS"
    APPROVE_JOIN = "APPROVE_JOIN"
    CREATE_INVITE = "CREATE_INVITE"
    VOICE_CONNECT = "VOICE_CONNECT"
    VOICE_SPEAK = "VOICE_SPEAK"
    ADMINISTRATOR = "ADMINISTRATOR"


ALL_PERMISSIONS_SET: frozenset[Permission] = frozenset(Permission)


@dataclass(frozen=True)
class PermissionSpec:
    """Declarative specification of permissions expected by a business operation.

    Attributes:
        must_have: Permissions that must all be granted for the operation to proceed.
        any_of: Permissions where at least one must be granted (if non-empty).
        may_have: Optional permissions inspected by the operation to enable extra capabilities.
    """

    must_have: frozenset[Permission] = field(default_factory=frozenset)
    any_of: frozenset[Permission] = field(default_factory=frozenset)
    may_have: frozenset[Permission] = field(default_factory=frozenset)

    @classmethod
    def of(
        cls,
        must_have: Iterable[Permission] | None = None,
        any_of: Iterable[Permission] | None = None,
        may_have: Iterable[Permission] | None = None,
    ) -> PermissionSpec:
        """Constructs a `PermissionSpec` from any iterable collections of permissions.

        Args:
            must_have: Mandatory permissions required simultaneously.
            any_of: Alternative permissions where at least one is required.
            may_have: Optional permissions evaluated for conditional branching.

        Returns:
            PermissionSpec: Immutable permission specification instance.
        """
        return cls(
            must_have=frozenset(must_have or ()),
            any_of=frozenset(any_of or ()),
            may_have=frozenset(may_have or ()),
        )


@dataclass(frozen=True)
class PermissionEvaluation:
    """Result of verifying a user's permissions against a `PermissionSpec`.

    Attributes:
        granted: Effective set of permissions granted to the user in the target context.
    """

    granted: frozenset[Permission]

    def has(self, permission: Permission) -> bool:
        """Checks whether a single permission is granted.

        Args:
            permission: The permission identifier to check.

        Returns:
            bool: True if granted, False otherwise.
        """
        return permission in self.granted

    def has_all(self, *permissions: Permission) -> bool:
        """Checks whether all specified permissions are granted.

        Args:
            *permissions: Variable number of permission identifiers.

        Returns:
            bool: True if every specified permission is granted.
        """
        return all(p in self.granted for p in permissions)

    def has_any(self, *permissions: Permission) -> bool:
        """Checks whether at least one of the specified permissions is granted.

        Args:
            *permissions: Variable number of permission identifiers.

        Returns:
            bool: True if at least one specified permission is granted.
        """
        return any(p in self.granted for p in permissions)

    def to_sorted_list(self) -> list[str]:
        """Serializes granted permissions into a deterministic list of strings.

        Returns:
            list[str]: Sorted list of permission string values.
        """
        return sorted(p.value for p in self.granted)


class IPermissionChecker(Protocol):
    """Port interface for resolving and verifying fandom/channel permissions."""

    async def resolve_permissions(
        self,
        user_id: uuid.UUID,
        fandom_id: uuid.UUID,
        channel_id: uuid.UUID | None = None,
    ) -> set[Permission]:
        """Resolves the effective set of permissions for a user in a fandom/channel."""
        ...

    async def verify(
        self,
        user_id: uuid.UUID,
        fandom_id: uuid.UUID,
        channel_id: uuid.UUID | None,
        spec: PermissionSpec,
        error_detail: str | None = None,
    ) -> PermissionEvaluation:
        """Verifies that a user's effective permissions satisfy `spec`."""
        ...


class BasePermissionChecker(ABC):
    """Abstract base checker implementing uniform `PermissionSpec` verification logic."""

    @abstractmethod
    async def resolve_permissions(
        self,
        user_id: uuid.UUID,
        fandom_id: uuid.UUID,
        channel_id: uuid.UUID | None = None,
    ) -> set[Permission]:
        """Resolves raw permissions for the given user, fandom, and optional channel."""

    async def verify(
        self,
        user_id: uuid.UUID,
        fandom_id: uuid.UUID,
        channel_id: uuid.UUID | None,
        spec: PermissionSpec,
        error_detail: str | None = None,
    ) -> PermissionEvaluation:
        """Evaluates `spec` against resolved permissions and raises 403 on violation.

        Args:
            user_id: Target user UUID.
            fandom_id: Target fandom UUID.
            channel_id: Optional target channel UUID.
            spec: Declarative permission requirements.
            error_detail: Custom Vietnamese error message if verification fails.

        Returns:
            PermissionEvaluation: Resolved capability context for downstream logic.

        Raises:
            HTTPException: 403 Forbidden if `must_have` or `any_of` constraints fail.
        """
        raw_permissions = await self.resolve_permissions(
            user_id=user_id,
            fandom_id=fandom_id,
            channel_id=channel_id,
        )
        effective: frozenset[Permission] = (
            ALL_PERMISSIONS_SET
            if Permission.ADMINISTRATOR in raw_permissions
            else frozenset(raw_permissions)
        )

        if spec.must_have and not spec.must_have.issubset(effective):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=error_detail or "Bạn không có quyền thực hiện thao tác này trên kênh.",
            )

        if spec.any_of and effective.isdisjoint(spec.any_of):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=error_detail or "Bạn không có đủ quyền hạn yêu cầu để thực hiện thao tác này.",
            )

        return PermissionEvaluation(granted=effective)


class MockPermissionChecker(BasePermissionChecker):
    """In-memory permission checker for unit and integration testing."""

    def __init__(
        self,
        granted: Iterable[Permission] | None = None,
        per_channel_granted: dict[uuid.UUID, set[Permission]] | None = None,
    ) -> None:
        """Initializes the mock checker with static or per-channel permission sets.

        Args:
            granted: Default permissions granted across all queries.
            per_channel_granted: Optional overrides keyed by `channel_id`.
        """
        self._granted: set[Permission] = set(granted or ())
        self._per_channel: dict[uuid.UUID, set[Permission]] = per_channel_granted or {}

    async def resolve_permissions(
        self,
        user_id: uuid.UUID,
        fandom_id: uuid.UUID,
        channel_id: uuid.UUID | None = None,
    ) -> set[Permission]:
        """Returns the configured mock permissions without database access."""
        if channel_id and channel_id in self._per_channel:
            base = set(self._per_channel[channel_id])
        else:
            base = set(self._granted)

        if Permission.ADMINISTRATOR in base:
            return set(ALL_PERMISSIONS_SET)
        return base


class DefaultMembershipPermissionAdapter(BasePermissionChecker):
    """Default permission adapter backed by Fandom ownership and membership status.

    Provides baseline access control for FR-05 prior to full RBAC bitmask role
    overrides in FR-06.
    """

    def __init__(self, db: AsyncSession) -> None:
        """Initializes the adapter with an active database session.

        Args:
            db: SQLAlchemy asynchronous session.
        """
        self._db = db

    async def resolve_permissions(
        self,
        user_id: uuid.UUID,
        fandom_id: uuid.UUID,
        channel_id: uuid.UUID | None = None,
    ) -> set[Permission]:
        """Resolves permissions based on Fandom ownership, membership state, and channel type.

        Args:
            user_id: Authenticated user UUID.
            fandom_id: Target fandom UUID.
            channel_id: Optional target channel UUID for channel-specific rules.

        Returns:
            set[Permission]: Effective permissions for the user.
        """
        from app.modules.chat.models import Channel
        from app.modules.fandom.models import Fandom, FandomMember
        from app.modules.rbac.models import MemberRole, PermissionBit, Role
        from sqlalchemy import or_

        fandom_res = await self._db.execute(
            select(Fandom).where(Fandom.id == fandom_id)
        )
        fandom = fandom_res.scalar_one_or_none()
        if not fandom:
            return set()

        if fandom.owner_id == user_id:
            return set(ALL_PERMISSIONS_SET)

        member_res = await self._db.execute(
            select(FandomMember).where(
                FandomMember.fandom_id == fandom_id,
                FandomMember.user_id == user_id,
            )
        )
        member = member_res.scalar_one_or_none()
        if not member or member.status == "BANNED":
            return set()

        now = datetime.now(timezone.utc)
        is_currently_muted = member.status == "MUTED" and (
            member.muted_until is None or member.muted_until > now
        )

        permissions: set[Permission] = {
            Permission.VIEW_CHANNEL,
            Permission.READ_MESSAGES,
            Permission.VOICE_CONNECT,
        }
        if not is_currently_muted:
            permissions.update(
                {
                    Permission.SEND_MESSAGES,
                    Permission.ATTACH_FILES,
                    Permission.EMBED_LINKS,
                    Permission.VOICE_SPEAK,
                }
            )

        # Retrieve active assigned roles for member
        role_res = await self._db.execute(
            select(Role)
            .join(MemberRole, MemberRole.role_id == Role.id)
            .where(
                MemberRole.fandom_id == fandom_id,
                MemberRole.user_id == user_id,
                or_(MemberRole.expires_at.is_(None), MemberRole.expires_at > now),
            )
        )
        roles = role_res.scalars().all()

        combined_bitmask = 0
        for r in roles:
            combined_bitmask |= r.permissions_bitmask

        if combined_bitmask & PermissionBit.ADMINISTRATOR:
            return set(ALL_PERMISSIONS_SET)

        if combined_bitmask & PermissionBit.READ_MESSAGES:
            permissions.add(Permission.READ_MESSAGES)
        if combined_bitmask & PermissionBit.SEND_MESSAGES and not is_currently_muted:
            permissions.add(Permission.SEND_MESSAGES)
        if combined_bitmask & PermissionBit.EMBED_LINKS and not is_currently_muted:
            permissions.add(Permission.EMBED_LINKS)
        if combined_bitmask & PermissionBit.ATTACH_FILES and not is_currently_muted:
            permissions.add(Permission.ATTACH_FILES)
        if combined_bitmask & PermissionBit.VOICE_CONNECT:
            permissions.add(Permission.VOICE_CONNECT)
        if combined_bitmask & PermissionBit.VOICE_SPEAK and not is_currently_muted:
            permissions.add(Permission.VOICE_SPEAK)
        if combined_bitmask & PermissionBit.MANAGE_CHANNELS:
            permissions.add(Permission.MANAGE_CHANNELS)
            permissions.add(Permission.SEND_ANNOUNCEMENT)
            permissions.add(Permission.BYPASS_SLOWMODE)
        if combined_bitmask & PermissionBit.MANAGE_ROLES:
            permissions.add(Permission.MANAGE_ROLES)
        if combined_bitmask & PermissionBit.MODERATE_CHAT:
            permissions.add(Permission.MODERATE_CHAT)
            permissions.add(Permission.BYPASS_SLOWMODE)
        if combined_bitmask & PermissionBit.MUTE_MEMBERS:
            permissions.add(Permission.MUTE_MEMBERS)
        if combined_bitmask & PermissionBit.KICK_MEMBERS:
            permissions.add(Permission.KICK_MEMBERS)
        if combined_bitmask & PermissionBit.BAN_MEMBERS:
            permissions.add(Permission.BAN_MEMBERS)
        if combined_bitmask & PermissionBit.APPROVE_JOIN:
            permissions.add(Permission.APPROVE_JOIN)
        if combined_bitmask & PermissionBit.CREATE_INVITE:
            permissions.add(Permission.CREATE_INVITE)
        if combined_bitmask & PermissionBit.BYPASS_SLOWMODE:
            permissions.add(Permission.BYPASS_SLOWMODE)

        if channel_id is not None:
            channel_res = await self._db.execute(
                select(Channel).where(
                    Channel.id == channel_id,
                    Channel.fandom_id == fandom_id,
                )
            )
            channel = channel_res.scalar_one_or_none()
            if channel:
                if channel.required_role_id is not None and Permission.MANAGE_CHANNELS not in permissions:
                    has_role = any(r.id == channel.required_role_id for r in roles)
                    if not has_role:
                        return set()

                if channel.is_membership_only and Permission.MANAGE_CHANNELS not in permissions:
                    has_membership = any(r.is_membership_tier for r in roles)
                    if not has_membership:
                        return set()

                if channel.is_announcement:
                    if Permission.SEND_ANNOUNCEMENT not in permissions and Permission.MANAGE_CHANNELS not in permissions:
                        permissions.discard(Permission.SEND_MESSAGES)
                        permissions.discard(Permission.ATTACH_FILES)
                        permissions.discard(Permission.EMBED_LINKS)
                if channel.type == "VOICE" and channel.voice_room_type == "STAGE_ROOM":
                    if Permission.MODERATE_CHAT not in permissions:
                        permissions.discard(Permission.VOICE_SPEAK)

        return permissions


async def get_permission_checker(
    db: AsyncSession = Depends(get_db),
) -> IPermissionChecker:
    """FastAPI dependency providing the active `IPermissionChecker` implementation.

    Args:
        db: Scoped database session.

    Returns:
        IPermissionChecker: Default membership permission adapter instance.
    """
    return DefaultMembershipPermissionAdapter(db=db)
