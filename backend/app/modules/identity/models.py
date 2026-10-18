"""Identity and Authentication Database Models.

This module defines the relational schema for User entities, System Roles,
Platform Types, and multi-device User Sessions with Refresh Token Rotation.
"""

import enum
import uuid
from datetime import datetime, timezone
from sqlalchemy import String, Boolean, DateTime, Text, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class SystemRole(str, enum.Enum):
    """System-level access roles for platform governance.

    Attributes:
        USER: Standard platform participant with basic interaction permissions.
        SYSTEM_MODERATOR: Content and community moderator with violation enforcement tools.
        SYSTEM_ADMIN: Supreme administrator with full infrastructure and user management access.
    """
    USER = "USER"
    SYSTEM_MODERATOR = "SYSTEM_MODERATOR"
    SYSTEM_ADMIN = "SYSTEM_ADMIN"


class PlatformType(str, enum.Enum):
    """Client platforms recognized by the single-session-per-platform policy.

    Attributes:
        MOBILE: Native Android or iOS mobile application (requires device identifier).
        DESKTOP: Native desktop application (Linux, Windows, macOS).
        WEB: Standard web browser client.
    """
    MOBILE = "MOBILE"
    DESKTOP = "DESKTOP"
    WEB = "WEB"


class User(Base):
    """User account model storing identity, credentials, and verification status.

    Attributes:
        id (UUID): Primary key uniquely identifying the user.
        email (str): Unique, indexed email address.
        username (str): Unique, indexed public username handle.
        password_hash (str | None): Argon2id hashed password (None for pure OAuth users).
        display_name (str): Public profile display name.
        avatar_url (str | None): Profile photo URL.
        bio (str | None): Short user biography.
        google_id (str | None): Linked Google subject ID (`sub`), uniquely indexed.
        is_email_verified (bool): Verification state of user's email address.
        system_role (str): Assigned SystemRole value ('USER', 'SYSTEM_MODERATOR', 'SYSTEM_ADMIN').
        is_active (bool): Active status; False denotes deactivated or soft-deleted accounts.
        deleted_at (datetime | None): Timestamp when account deletion was executed.
        created_at (datetime): Account creation timestamp.
        updated_at (datetime): Timestamp of last record update.
        wallet (Wallet): One-to-one relationship to User's financial wallet.
        sessions (list[UserSession]): One-to-many active and historical device sessions.
        fandoms_owned (list[Fandom]): Fandom communities created and owned by this user.
        fandom_memberships (list[FandomMember]): Memberships in fandom communities.
    """
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    email: Mapped[str] = mapped_column(
        String(255), unique=True, index=True, nullable=False
    )
    username: Mapped[str] = mapped_column(
        String(50), unique=True, index=True, nullable=False
    )
    password_hash: Mapped[str | None] = mapped_column(String(255), nullable=True)
    display_name: Mapped[str] = mapped_column(String(100), nullable=False)
    avatar_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    bio: Mapped[str | None] = mapped_column(Text, nullable=True)
    google_id: Mapped[str | None] = mapped_column(String(100), unique=True, nullable=True, index=True)
    is_email_verified: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    system_role: Mapped[str] = mapped_column(
        String(50), default=SystemRole.USER.value, nullable=False, index=True
    )
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False, index=True)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    # Relationships
    wallet = relationship("Wallet", back_populates="user", uselist=False, cascade="all, delete-orphan")
    sessions = relationship("UserSession", back_populates="user", cascade="all, delete-orphan")
    fandoms_owned = relationship("Fandom", back_populates="owner")
    fandom_memberships = relationship("FandomMember", back_populates="user")


class UserSession(Base):
    """Device session record tracking active tokens and device details.

    Attributes:
        id (UUID): Primary key identifying this specific device session.
        user_id (UUID): Foreign key to the parent User account.
        platform (str): Client platform category ('MOBILE', 'DESKTOP', 'WEB').
        device_id (str | None): Client hardware identifier (mandatory for MOBILE).
        device_name (str): Parsed human-friendly client hardware and browser label.
        ip_address (str | None): Client IP recorded during session issuance.
        user_agent (str | None): Full raw User-Agent string.
        refresh_token_hash (str): SHA-256 hash of the active refresh token.
        is_active (bool): Active session flag (False if logged out or replaced).
        last_active_at (datetime): Timestamp when the session was last refreshed.
        expires_at (datetime): Expiration cutoff timestamp for the session.
        created_at (datetime): Timestamp when the session was first initiated.
        user (User): Relationship back to the owner User.
    """
    __tablename__ = "user_sessions"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    platform: Mapped[str] = mapped_column(
        String(20), nullable=False, index=True
    )
    device_id: Mapped[str | None] = mapped_column(
        String(100), nullable=True, index=True
    )
    device_name: Mapped[str] = mapped_column(
        String(150), nullable=False, default="Unknown Device"
    )
    ip_address: Mapped[str | None] = mapped_column(String(45), nullable=True)
    user_agent: Mapped[str | None] = mapped_column(Text, nullable=True)
    refresh_token_hash: Mapped[str] = mapped_column(String(255), index=True, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False, index=True)
    last_active_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )

    # Relationships
    user = relationship("User", back_populates="sessions")
