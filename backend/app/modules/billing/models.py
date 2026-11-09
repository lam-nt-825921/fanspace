import uuid
from datetime import datetime, timezone
from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Integer,
    JSON,
    String,
    Text,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class Wallet(Base):
    __tablename__ = "wallets"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False
    )
    coin_balance: Mapped[int] = mapped_column(BigInteger, default=0, nullable=False)
    locked_balance: Mapped[int] = mapped_column(BigInteger, default=0, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    # Relationships
    user = relationship("User", back_populates="wallet")


class FandomBankAccount(Base):
    """Receiving bank account linked by the Fandom Owner for SePay VietQR payments."""

    __tablename__ = "fandom_bank_accounts"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    fandom_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("fandoms.id", ondelete="CASCADE"),
        unique=True,
        index=True,
        nullable=False,
    )
    bank_code: Mapped[str] = mapped_column(String(50), nullable=False)
    account_number: Mapped[str] = mapped_column(String(50), nullable=False)
    account_name: Mapped[str] = mapped_column(String(100), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
    )


class PaymentOrder(Base):
    """Order entity in the 3-Way Matching Model (Product - Order - Transaction).

    Captures a user's intent to purchase a specific Membership Tier Role at a
    frozen price and duration, paired with a SePay default payment code (`DH...`).
    """

    __tablename__ = "payment_orders"
    __table_args__ = (
        CheckConstraint("amount_vnd > 0", name="ck_payment_orders_amount_positive"),
        CheckConstraint("paid_amount_vnd >= 0", name="ck_payment_orders_paid_non_negative"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    order_code: Mapped[str] = mapped_column(
        String(32), unique=True, index=True, nullable=False
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    fandom_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("fandoms.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    role_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("roles.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    role_name_snapshot: Mapped[str] = mapped_column(String(100), nullable=False)
    amount_vnd: Mapped[int] = mapped_column(BigInteger, nullable=False)
    paid_amount_vnd: Mapped[int] = mapped_column(BigInteger, default=0, nullable=False)
    duration_days: Mapped[int] = mapped_column(Integer, default=30, nullable=False)
    bank_code: Mapped[str] = mapped_column(String(50), nullable=False)
    account_number: Mapped[str] = mapped_column(String(50), nullable=False)
    account_name: Mapped[str] = mapped_column(String(100), nullable=False)
    qr_url: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(
        String(20), default="PENDING", index=True, nullable=False
    )  # PENDING, PAID, UNDERPAID, OVERPAID, EXPIRED, CANCELLED
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    paid_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    # Relationships
    transactions = relationship(
        "PaymentTransaction",
        back_populates="order",
        order_by="PaymentTransaction.created_at.desc()",
    )


class PaymentTransaction(Base):
    """Immutable Audit Trail & Transaction entity in the 3-Way Matching Model.

    Records every incoming/outgoing bank notification from SePay Webhook, enforcing
    strict idempotency via `sepay_transaction_id` and preserving raw bank evidence.
    """

    __tablename__ = "payment_transactions"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    sepay_transaction_id: Mapped[int] = mapped_column(
        BigInteger, unique=True, index=True, nullable=False
    )
    order_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("payment_orders.id", ondelete="SET NULL"),
        index=True,
        nullable=True,
    )
    user_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        index=True,
        nullable=True,
    )
    fandom_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("fandoms.id", ondelete="SET NULL"),
        index=True,
        nullable=True,
    )
    gateway: Mapped[str] = mapped_column(String(50), nullable=False)
    transaction_date: Mapped[str] = mapped_column(String(50), nullable=False)
    account_number: Mapped[str] = mapped_column(String(50), nullable=False)
    sub_account: Mapped[str | None] = mapped_column(String(50), nullable=True)
    transfer_type: Mapped[str] = mapped_column(String(10), default="in", nullable=False)
    transfer_amount: Mapped[int] = mapped_column(BigInteger, nullable=False)
    accumulated: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    code: Mapped[str | None] = mapped_column(String(100), nullable=True)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    reference_code: Mapped[str | None] = mapped_column(String(100), nullable=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    raw_payload: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    reconciliation_status: Mapped[str] = mapped_column(
        String(30), index=True, nullable=False
    )  # MATCHED, OVERPAID, UNDERPAID, EXPIRED_ORDER, ALREADY_PAID_ORDER, UNMATCHED_ORDER, IGNORED_OUTGOING, MANUAL_MATCHED
    audit_note: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    # Relationships
    order = relationship("PaymentOrder", back_populates="transactions")
