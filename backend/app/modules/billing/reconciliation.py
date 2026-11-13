"""Pure domain calculations, SePay gateway cryptography, and 3-Way Matching engine.

Separates business rules, payload builders, and mathematical/cryptographic computations
from database queries so `BillingService` focuses strictly on data retrieval,
validation, and ACID transaction orchestration.
"""

from __future__ import annotations

import hashlib
import hmac
import re
import secrets
import urllib.parse
import uuid
from collections.abc import Iterable, Mapping
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from fastapi import HTTPException, status

from app.core.config import get_settings
from app.modules.billing.models import PaymentOrder, PaymentTransaction
from app.modules.billing.schemas import (
    FandomLeaderboardOut,
    FandomLedgerResponse,
    LeaderboardSpendingEntryOut,
    LeaderboardStreakEntryOut,
    MembershipTierOut,
    PaymentOrderOut,
    PaymentTransactionOut,
    SepaySimulateRequest,
    SepayWebhookPayload,
)
from app.modules.rbac.models import PermissionBit, Role

settings = get_settings()

MAX_MEMBERSHIP_TIERS_PER_FANDOM: int = 4
_DH_CODE_PATTERN = re.compile(r"\b(DH\d{4,12})\b", re.IGNORECASE)
_DH_CODE_FALLBACK_PATTERN = re.compile(r"(DH\d{4,12})", re.IGNORECASE)


@dataclass(frozen=True)
class ReconciliationDecision:
    """Immutable outcome produced by the 3-Way Matching domain engine."""

    reconciliation_status: str
    new_order_status: str
    new_paid_amount_vnd: int
    should_provision_role: bool
    mark_paid_timestamp: bool
    audit_note: str


@dataclass(frozen=True)
class MembershipStreakUpdate:
    """Immutable calculation result for membership expiration and renewal streak."""

    new_expires_at: datetime
    streak_count: int
    streak_days: int
    streak_started_at: datetime


def compute_tier_permissions_bitmask(requested_bitmask: int) -> int:
    """Computes effective permission bitmask for a paid Membership Tier Role."""
    return (
        requested_bitmask
        | PermissionBit.READ_MESSAGES
        | PermissionBit.SEND_MESSAGES
        | PermissionBit.EMBED_LINKS
        | PermissionBit.ATTACH_FILES
        | PermissionBit.VOICE_CONNECT
    )


def build_sepay_qr_url(
    bank_code: str,
    account_number: str,
    amount_vnd: int,
    order_code: str,
) -> str:
    """Builds the official SePay VietQR image URL (`qr.sepay.vn/img`)."""
    params = urllib.parse.urlencode(
        {
            "acc": account_number.strip(),
            "bank": bank_code.strip(),
            "amount": str(amount_vnd),
            "des": order_code.strip(),
        }
    )
    return f"https://qr.sepay.vn/img?{params}"


def compute_sepay_hmac_signature(
    raw_body: bytes,
    secret: str,
    timestamp: str | None = None,
) -> str:
    """Computes the lowercase hex HMAC-SHA256 signature for a SePay webhook payload."""
    message = f"{timestamp}.".encode("utf-8") + raw_body if timestamp else raw_body
    return hmac.new(
        secret.encode("utf-8"),
        message,
        hashlib.sha256,
    ).hexdigest()


def verify_sepay_webhook_signature(
    raw_body: bytes,
    headers: Mapping[str, str],
    secret: str | None = None,
) -> None:
    """Verifies incoming SePay webhook authenticity using HMAC-SHA256 (`X-SePay-Signature`)."""
    active_secret = (secret or settings.SEPAY_WEBHOOK_SECRET).strip()
    lower_headers = {k.lower(): v for k, v in headers.items()}

    sig_header = (
        lower_headers.get("x-sepay-signature")
        or lower_headers.get("x-signature")
        or ""
    ).strip()
    timestamp = (lower_headers.get("x-sepay-timestamp") or "").strip()

    if sig_header:
        incoming_hash = (
            sig_header[7:].strip()
            if sig_header.lower().startswith("sha256=")
            else sig_header
        )
        candidates: list[str] = [
            compute_sepay_hmac_signature(raw_body, active_secret, None)
        ]
        if timestamp:
            candidates.insert(
                0,
                compute_sepay_hmac_signature(raw_body, active_secret, timestamp),
            )

        if any(
            hmac.compare_digest(incoming_hash.lower(), expected.lower())
            for expected in candidates
        ):
            return

    auth_header = (lower_headers.get("authorization") or "").strip()
    if auth_header.lower().startswith("apikey "):
        provided_key = auth_header[7:].strip()
        if hmac.compare_digest(provided_key, active_secret):
            return

    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Xác thực chữ ký Webhook SePay (HMAC-SHA256) không hợp lệ.",
    )


def extract_sepay_order_code(payload: SepayWebhookPayload) -> str | None:
    """Extracts the default SePay payment code (`DH...`) from `code` or `content`."""
    prefix = settings.SEPAY_PAYMENT_CODE_PREFIX.upper()
    if payload.code:
        candidate = payload.code.strip().upper()
        if candidate.startswith(prefix):
            return candidate

    search_text = f"{payload.content or ''} {payload.description or ''}"
    match = _DH_CODE_PATTERN.search(search_text)
    if match:
        return match.group(1).upper()

    fallback = _DH_CODE_FALLBACK_PATTERN.search(search_text)
    if fallback:
        return fallback.group(1).upper()

    if payload.code and payload.code.strip():
        return payload.code.strip().upper()

    return None


def calculate_membership_expiry(
    current_expires_at: datetime | None,
    duration_days: int,
    now: datetime,
) -> datetime:
    """Calculates new membership expiration timestamp, stacking remaining active time on renewal."""
    base_time = (
        current_expires_at
        if (current_expires_at is not None and current_expires_at > now)
        else now
    )
    return base_time + timedelta(days=duration_days)


def calculate_membership_streak(
    current_expires_at: datetime | None,
    current_streak_count: int | None,
    current_streak_days: int | None,
    current_streak_started_at: datetime | None,
    duration_days: int,
    now: datetime,
    streak_grace_hours: int = 24,
) -> MembershipStreakUpdate:
    """Calculates updated membership expiration and consecutive renewal streak metrics."""
    new_expires_at = calculate_membership_expiry(
        current_expires_at=current_expires_at,
        duration_days=duration_days,
        now=now,
    )
    grace_cutoff = now - timedelta(hours=streak_grace_hours)
    is_consecutive = (
        current_expires_at is not None
        and current_expires_at >= grace_cutoff
        and (current_streak_count or 0) > 0
    )
    if is_consecutive:
        return MembershipStreakUpdate(
            new_expires_at=new_expires_at,
            streak_count=int(current_streak_count or 0) + 1,
            streak_days=int(current_streak_days or 0) + int(duration_days),
            streak_started_at=current_streak_started_at or now,
        )
    return MembershipStreakUpdate(
        new_expires_at=new_expires_at,
        streak_count=1,
        streak_days=int(duration_days),
        streak_started_at=now,
    )


def evaluate_3way_reconciliation(
    order: PaymentOrder,
    transfer_amount: int,
    now: datetime,
    grace_minutes: int | None = None,
) -> ReconciliationDecision:
    """Pure 3-Way Matching rule evaluator comparing Order state, expiry, and transfer amount."""
    effective_grace = (
        grace_minutes
        if grace_minutes is not None
        else settings.SEPAY_GRACE_PERIOD_MINUTES
    )

    if order.status in ("PAID", "OVERPAID"):
        return ReconciliationDecision(
            reconciliation_status="ALREADY_PAID_ORDER",
            new_order_status=order.status,
            new_paid_amount_vnd=order.paid_amount_vnd or 0,
            should_provision_role=False,
            mark_paid_timestamp=False,
            audit_note=(
                f"Đơn hàng {order.order_code} đã hoàn tất thanh toán trước đó. "
                "Cảnh báo chuyển khoản dư/trùng."
            ),
        )

    grace_deadline = order.expires_at + timedelta(minutes=effective_grace)
    if order.status in ("CANCELLED", "EXPIRED") or (
        order.status == "PENDING" and now > grace_deadline
    ):
        next_status = "EXPIRED" if order.status == "PENDING" else order.status
        return ReconciliationDecision(
            reconciliation_status="EXPIRED_ORDER",
            new_order_status=next_status,
            new_paid_amount_vnd=order.paid_amount_vnd or 0,
            should_provision_role=False,
            mark_paid_timestamp=False,
            audit_note=(
                f"Tiền về sau khi đơn hàng {order.order_code} đã hết hạn hoặc bị hủy "
                f"(Trạng thái đơn: {next_status}). Chờ Chủ Fandom duyệt thủ công."
            ),
        )

    accumulated_paid = (order.paid_amount_vnd or 0) + int(transfer_amount)
    if accumulated_paid < order.amount_vnd:
        shortfall = order.amount_vnd - accumulated_paid
        return ReconciliationDecision(
            reconciliation_status="UNDERPAID",
            new_order_status="UNDERPAID",
            new_paid_amount_vnd=accumulated_paid,
            should_provision_role=False,
            mark_paid_timestamp=False,
            audit_note=(
                f"Chuyển thiếu tiền cho đơn {order.order_code}: nhận {transfer_amount:,}đ, "
                f"lũy kế {accumulated_paid:,}/{order.amount_vnd:,}đ (còn thiếu {shortfall:,}đ)."
            ),
        )

    if accumulated_paid > order.amount_vnd:
        surplus = accumulated_paid - order.amount_vnd
        return ReconciliationDecision(
            reconciliation_status="OVERPAID",
            new_order_status="OVERPAID",
            new_paid_amount_vnd=accumulated_paid,
            should_provision_role=True,
            mark_paid_timestamp=True,
            audit_note=(
                f"Khớp đơn {order.order_code} (Chuyển dư {surplus:,}đ): "
                f"nhận {accumulated_paid:,}/{order.amount_vnd:,}đ. "
                f"Đã kích hoạt gói '{order.role_name_snapshot}'."
            ),
        )

    return ReconciliationDecision(
        reconciliation_status="MATCHED",
        new_order_status="PAID",
        new_paid_amount_vnd=accumulated_paid,
        should_provision_role=True,
        mark_paid_timestamp=True,
        audit_note=(
            f"Đối soát 3 bên khớp hoàn hảo đơn {order.order_code}: "
            f"nhận đủ {order.amount_vnd:,}đ. "
            f"Đã kích hoạt gói '{order.role_name_snapshot}'."
        ),
    )


def build_transaction_entity(
    payload: SepayWebhookPayload,
    reconciliation_status: str,
    audit_note: str,
    code: str | None = None,
    order_id: uuid.UUID | None = None,
    user_id: uuid.UUID | None = None,
    fandom_id: uuid.UUID | None = None,
) -> PaymentTransaction:
    """Constructs an immutable `PaymentTransaction` ORM audit entity from a SePay payload."""
    return PaymentTransaction(
        sepay_transaction_id=payload.id,
        order_id=order_id,
        user_id=user_id,
        fandom_id=fandom_id,
        gateway=payload.gateway,
        transaction_date=payload.transactionDate,
        account_number=payload.accountNumber,
        sub_account=payload.subAccount,
        transfer_type=(payload.transferType or "in").lower(),
        transfer_amount=payload.transferAmount,
        accumulated=payload.accumulated,
        code=code,
        content=payload.content,
        reference_code=payload.referenceCode,
        description=payload.description,
        raw_payload=payload.model_dump(mode="json"),
        reconciliation_status=reconciliation_status,
        audit_note=audit_note,
    )


def build_simulated_sepay_payload(
    data: SepaySimulateRequest,
    order: PaymentOrder | None,
) -> SepayWebhookPayload:
    """Builds a synthetic `SepayWebhookPayload` for sandbox testing and simulation."""
    normalized_code = data.order_code.strip().upper()
    remaining = (
        max(1, order.amount_vnd - (order.paid_amount_vnd or 0))
        if order
        else 50_000
    )
    amount = data.transfer_amount if data.transfer_amount is not None else remaining
    bank_code = data.gateway or (order.bank_code if order else "MBBank")
    acc_number = order.account_number if order else "0000123456789"
    sepay_id = secrets.randbelow(900_000_000) + 100_000_000
    now_str = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    content_text = data.custom_content or f"CHUYEN TIEN {normalized_code} FANSPACE"
    extracted_in_custom = (
        None if data.custom_content is not None else normalized_code
    )
    return SepayWebhookPayload(
        id=sepay_id,
        gateway=bank_code,
        transactionDate=now_str,
        accountNumber=acc_number,
        subAccount=None,
        code=extracted_in_custom,
        content=content_text,
        transferType="in",
        transferAmount=amount,
        accumulated=amount,
        referenceCode=f"FT{sepay_id}",
        description=f"Simulated SePay Webhook ({normalized_code})",
    )


def serialize_tier_out(
    tier: Role,
    is_owned: bool = False,
    expires_at: datetime | None = None,
) -> MembershipTierOut:
    """Maps a paid `Role` ORM instance into `MembershipTierOut`."""
    from app.modules.rbac.models import MembershipPerkBit

    return MembershipTierOut(
        id=tier.id,
        fandom_id=tier.fandom_id,
        name=tier.name,
        color_hex=tier.color_hex,
        icon_url=tier.icon_url,
        priority=tier.priority,
        permissions_bitmask=tier.permissions_bitmask,
        membership_perks_bitmask=(
            tier.membership_perks_bitmask
            if tier.membership_perks_bitmask is not None
            else int(MembershipPerkBit.DEFAULT_TIER_PERKS)
        ),
        tier_level=tier.tier_level or 1,
        price_fiat_vnd=tier.price_fiat_vnd or 0,
        duration_days=tier.duration_days or 30,
        is_owned=is_owned,
        owned_expires_at=expires_at,
        created_at=tier.created_at,
    )


def serialize_transaction_out(
    tx: PaymentTransaction,
    order_code: str | None = None,
) -> PaymentTransactionOut:
    """Maps a `PaymentTransaction` ORM instance into `PaymentTransactionOut`."""
    return PaymentTransactionOut(
        id=tx.id,
        sepay_transaction_id=tx.sepay_transaction_id,
        order_id=tx.order_id,
        order_code=order_code or tx.code,
        user_id=tx.user_id,
        fandom_id=tx.fandom_id,
        gateway=tx.gateway,
        transaction_date=tx.transaction_date,
        account_number=tx.account_number,
        transfer_type=tx.transfer_type,
        transfer_amount=tx.transfer_amount,
        code=tx.code,
        content=tx.content,
        reference_code=tx.reference_code,
        reconciliation_status=tx.reconciliation_status,
        audit_note=tx.audit_note,
        created_at=tx.created_at,
    )


def serialize_order_out(
    order: PaymentOrder,
    transactions: Iterable[PaymentTransaction],
    member_role_expires_at: datetime | None = None,
) -> PaymentOrderOut:
    """Maps a `PaymentOrder` ORM instance and its transactions into `PaymentOrderOut`."""
    tx_list = [serialize_transaction_out(t, order.order_code) for t in transactions]
    remaining = max(0, order.amount_vnd - order.paid_amount_vnd)
    return PaymentOrderOut(
        id=order.id,
        order_code=order.order_code,
        user_id=order.user_id,
        fandom_id=order.fandom_id,
        role_id=order.role_id,
        role_name=order.role_name_snapshot,
        amount_vnd=order.amount_vnd,
        paid_amount_vnd=order.paid_amount_vnd,
        remaining_amount_vnd=remaining,
        duration_days=order.duration_days,
        bank_code=order.bank_code,
        account_number=order.account_number,
        account_name=order.account_name,
        qr_url=order.qr_url,
        status=order.status,
        expires_at=order.expires_at,
        paid_at=order.paid_at,
        member_role_expires_at=member_role_expires_at,
        created_at=order.created_at,
        transactions=tx_list,
    )


def build_fandom_ledger_response(
    fandom_id: uuid.UUID,
    total_revenue_vnd: int,
    orders: list[PaymentOrder],
    transactions: list[PaymentTransaction],
) -> FandomLedgerResponse:
    """Aggregates ledger metrics and serializes orders & audit transactions."""
    order_map = {o.id: o.order_code for o in orders}
    paid_orders_count = sum(1 for o in orders if o.status in ("PAID", "OVERPAID"))
    discrepant_count = sum(
        1
        for t in transactions
        if t.reconciliation_status
        in ("UNDERPAID", "OVERPAID", "UNMATCHED_ORDER", "EXPIRED_ORDER")
    )
    tx_by_order: dict[uuid.UUID, list[PaymentTransaction]] = {}
    for t in transactions:
        if t.order_id:
            tx_by_order.setdefault(t.order_id, []).append(t)

    return FandomLedgerResponse(
        fandom_id=fandom_id,
        total_revenue_vnd=total_revenue_vnd,
        paid_orders_count=paid_orders_count,
        discrepant_transactions_count=discrepant_count,
        transactions=[
            serialize_transaction_out(t, order_map.get(t.order_id))
            for t in transactions
        ],
        orders=[
            serialize_order_out(o, transactions=tx_by_order.get(o.id, []))
            for o in orders
        ],
    )


def build_fandom_leaderboard_response(
    fandom_id: uuid.UUID,
    raw_spending: Iterable[Mapping[str, object]],
    raw_streaks: Iterable[Mapping[str, object]],
    current_user_id: uuid.UUID | None = None,
    limit: int = 50,
) -> FandomLeaderboardOut:
    """Sorts and assigns 1-based rankings for Spending and Streak leaderboard tabs."""
    sorted_spending = sorted(
        raw_spending,
        key=lambda item: (
            -int(item.get("total_spent_vnd") or 0),
            -int(item.get("paid_orders_count") or 0),
            str(item.get("username") or ""),
        ),
    )
    spending_entries: list[LeaderboardSpendingEntryOut] = []
    my_spending_entry: LeaderboardSpendingEntryOut | None = None
    for idx, row in enumerate(sorted_spending, start=1):
        entry = LeaderboardSpendingEntryOut(
            rank=idx,
            user_id=row["user_id"],
            username=str(row["username"]),
            display_name=row.get("display_name"),
            avatar_url=row.get("avatar_url"),
            total_spent_vnd=int(row.get("total_spent_vnd") or 0),
            paid_orders_count=int(row.get("paid_orders_count") or 0),
            highest_tier_name=row.get("highest_tier_name"),
            highest_tier_level=row.get("highest_tier_level"),
            highest_tier_color_hex=row.get("highest_tier_color_hex"),
        )
        if current_user_id is not None and entry.user_id == current_user_id:
            my_spending_entry = entry
        if len(spending_entries) < limit:
            spending_entries.append(entry)

    sorted_streaks = sorted(
        raw_streaks,
        key=lambda item: (
            -int(item.get("streak_count") or 0),
            -int(item.get("streak_days") or 0),
            -int(item.get("tier_level") or 0),
            str(item.get("username") or ""),
        ),
    )
    streak_entries: list[LeaderboardStreakEntryOut] = []
    my_streak_entry: LeaderboardStreakEntryOut | None = None
    for idx, row in enumerate(sorted_streaks, start=1):
        entry = LeaderboardStreakEntryOut(
            rank=idx,
            user_id=row["user_id"],
            username=str(row["username"]),
            display_name=row.get("display_name"),
            avatar_url=row.get("avatar_url"),
            streak_count=int(row.get("streak_count") or 1),
            streak_days=int(row.get("streak_days") or 0),
            tier_name=str(row["tier_name"]),
            tier_level=int(row.get("tier_level") or 1),
            tier_color_hex=str(row.get("tier_color_hex") or "#7C4DFF"),
            streak_started_at=row.get("streak_started_at"),
            expires_at=row.get("expires_at"),
            is_active=bool(row.get("is_active", True)),
        )
        if current_user_id is not None and entry.user_id == current_user_id:
            my_streak_entry = entry
        if len(streak_entries) < limit:
            streak_entries.append(entry)

    return FandomLeaderboardOut(
        fandom_id=fandom_id,
        spending_leaderboard=spending_entries,
        streak_leaderboard=streak_entries,
        my_spending_entry=my_spending_entry,
        my_streak_entry=my_streak_entry,
    )

