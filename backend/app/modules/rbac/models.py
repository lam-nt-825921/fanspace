import uuid
from datetime import datetime, timezone
from sqlalchemy import String, Boolean, Integer, BigInteger, DateTime, Text, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


# Permission Bitmask Constants O(1)
class PermissionBit:
    READ_MESSAGES   = 1 << 0  # 1
    SEND_MESSAGES   = 1 << 1  # 2
    EMBED_LINKS     = 1 << 2  # 4
    ATTACH_FILES    = 1 << 3  # 8
    VOICE_CONNECT   = 1 << 4  # 16
    VOICE_SPEAK     = 1 << 5  # 32
    MANAGE_CHANNELS = 1 << 6  # 64
    MANAGE_ROLES    = 1 << 7  # 128
    MODERATE_CHAT   = 1 << 8  # 256 (Delete/Pin messages)
    MUTE_MEMBERS    = 1 << 9  # 512
    KICK_MEMBERS    = 1 << 10 # 1024
    BAN_MEMBERS     = 1 << 11 # 2048
    ADMINISTRATOR   = 1 << 12 # 4096 (All permissions)


class Role(Base):
    __tablename__ = "roles"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    fandom_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("fandoms.id", ondelete="CASCADE"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(String(50), nullable=False)
    color_hex: Mapped[str] = mapped_column(String(7), default="#808080", nullable=False)
    priority: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    permissions_bitmask: Mapped[int] = mapped_column(BigInteger, default=0, nullable=False)
    is_preset_mod: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    is_membership_tier: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    tier_level: Mapped[int | None] = mapped_column(Integer, nullable=True)
    icon_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    price_coins: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    price_fiat_vnd: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    duration_days: Mapped[int | None] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )

    # Relationships
    fandom = relationship("Fandom", back_populates="roles")
    member_assignments = relationship("MemberRole", back_populates="role", cascade="all, delete-orphan")


class MemberRole(Base):
    __tablename__ = "member_roles"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    fandom_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("fandoms.id", ondelete="CASCADE"), nullable=False
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    role_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("roles.id", ondelete="CASCADE"), nullable=False, index=True
    )
    assigned_by: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    assigned_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    # Relationships
    role = relationship("Role", back_populates="member_assignments")
