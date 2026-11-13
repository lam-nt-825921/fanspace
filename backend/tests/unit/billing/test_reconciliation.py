"""Unit tests for pure domain calculations and 3-Way Matching in `reconciliation.py`."""

import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi import HTTPException

from app.modules.billing.models import PaymentOrder
from app.modules.billing.reconciliation import (
    build_sepay_qr_url,
    build_fandom_leaderboard_response,
    calculate_membership_expiry,
    calculate_membership_streak,
    compute_sepay_hmac_signature,
    evaluate_3way_reconciliation,
    extract_sepay_order_code,
    verify_sepay_webhook_signature,
)
from app.modules.billing.schemas import SepayWebhookPayload


def _make_order(
    order_code: str = "DH12345678",
    amount_vnd: int = 50_000,
    paid_amount_vnd: int = 0,
    status: str = "PENDING",
    expires_at: datetime | None = None,
) -> PaymentOrder:
    now = datetime.now(timezone.utc)
    return PaymentOrder(
        id=uuid.uuid4(),
        order_code=order_code,
        user_id=uuid.uuid4(),
        fandom_id=uuid.uuid4(),
        role_id=uuid.uuid4(),
        role_name_snapshot="Fan Cứng VIP",
        amount_vnd=amount_vnd,
        paid_amount_vnd=paid_amount_vnd,
        duration_days=30,
        bank_code="MBBank",
        account_number="0389123456",
        account_name="NGUYEN VAN A",
        qr_url="https://qr.sepay.vn/img?acc=0389123456&bank=MBBank&amount=50000&des=DH12345678",
        status=status,
        expires_at=expires_at or (now + timedelta(minutes=15)),
        created_at=now,
        updated_at=now,
    )


def test_build_sepay_qr_url_and_extract_code():
    """Verifies SePay VietQR URL formatting and default DH payment code extraction."""
    url = build_sepay_qr_url("MBBank", "0389123456", 50000, "DH87654321")
    assert url.startswith("https://qr.sepay.vn/img?")
    assert "acc=0389123456" in url
    assert "bank=MBBank" in url
    assert "amount=50000" in url
    assert "des=DH87654321" in url

    p1 = SepayWebhookPayload(
        id=1,
        code="dh87654321",
        content="MBVCB.123.dh87654321.CT",
        transferAmount=50000,
    )
    assert extract_sepay_order_code(p1) == "DH87654321"

    p2 = SepayWebhookPayload(
        id=2,
        code=None,
        content="Chuyen khoan mua goi DH99887766 cam on",
        transferAmount=50000,
    )
    assert extract_sepay_order_code(p2) == "DH99887766"


def test_hmac_sha256_signature_verification():
    """Verifies HMAC-SHA256 webhook signature validation and tamper rejection."""
    raw = b'{"id":100,"transferAmount":50000,"code":"DH12345678"}'
    secret = "unit_test_secret_key"
    ts = "1731190000"
    sig = compute_sepay_hmac_signature(raw, secret, ts)

    verify_sepay_webhook_signature(
        raw_body=raw,
        headers={"X-SePay-Signature": f"sha256={sig}", "X-SePay-Timestamp": ts},
        secret=secret,
    )

    with pytest.raises(HTTPException) as exc_info:
        verify_sepay_webhook_signature(
            raw_body=raw + b"tampered",
            headers={"X-SePay-Signature": f"sha256={sig}", "X-SePay-Timestamp": ts},
            secret=secret,
        )
    assert exc_info.value.status_code == 401


def test_evaluate_3way_reconciliation_states_and_expiry_stacking():
    """Verifies 3-Way Matching pure decision rules across MATCHED, UNDERPAID, OVERPAID, EXPIRED."""
    now = datetime.now(timezone.utc)

    # 1. Exact Match
    order1 = _make_order(amount_vnd=50_000)
    d_match = evaluate_3way_reconciliation(order1, 50_000, now)
    assert d_match.reconciliation_status == "MATCHED"
    assert d_match.new_order_status == "PAID"
    assert d_match.should_provision_role is True

    # 2. Underpaid -> then top-up
    order2 = _make_order(amount_vnd=100_000)
    d_under = evaluate_3way_reconciliation(order2, 40_000, now)
    assert d_under.reconciliation_status == "UNDERPAID"
    assert d_under.new_order_status == "UNDERPAID"
    assert d_under.new_paid_amount_vnd == 40_000
    assert d_under.should_provision_role is False

    # 3. Overpaid
    order3 = _make_order(amount_vnd=50_000)
    d_over = evaluate_3way_reconciliation(order3, 65_000, now)
    assert d_over.reconciliation_status == "OVERPAID"
    assert d_over.new_order_status == "OVERPAID"
    assert d_over.should_provision_role is True

    # 4. Expired beyond grace period
    expired_order = _make_order(
        amount_vnd=50_000,
        expires_at=now - timedelta(minutes=20),
    )
    d_exp = evaluate_3way_reconciliation(expired_order, 50_000, now, grace_minutes=5)
    assert d_exp.reconciliation_status == "EXPIRED_ORDER"
    assert d_exp.new_order_status == "EXPIRED"
    assert d_exp.should_provision_role is False

    # 5. Membership expiry stacking
    first_expiry = calculate_membership_expiry(None, 30, now)
    stacked_expiry = calculate_membership_expiry(first_expiry, 30, now)
    assert (stacked_expiry - now).days == 60


def test_calculate_membership_streak_progression_and_reset():
    """Verifies streak increments on consecutive renewals and resets when expired beyond grace window."""
    now = datetime.now(timezone.utc)

    # First subscription
    s1 = calculate_membership_streak(
        current_expires_at=None,
        current_streak_count=0,
        current_streak_days=0,
        current_streak_started_at=None,
        duration_days=30,
        now=now,
    )
    assert s1.streak_count == 1
    assert s1.streak_days == 30
    assert s1.streak_started_at == now
    assert (s1.new_expires_at - now).days == 30

    # Consecutive renewal while still active
    s2 = calculate_membership_streak(
        current_expires_at=s1.new_expires_at,
        current_streak_count=s1.streak_count,
        current_streak_days=s1.streak_days,
        current_streak_started_at=s1.streak_started_at,
        duration_days=30,
        now=now + timedelta(days=20),
    )
    assert s2.streak_count == 2
    assert s2.streak_days == 60
    assert s2.streak_started_at == now
    assert (s2.new_expires_at - now).days == 60

    # Consecutive renewal within 24h grace period after expiry
    grace_now = s2.new_expires_at + timedelta(hours=12)
    s3 = calculate_membership_streak(
        current_expires_at=s2.new_expires_at,
        current_streak_count=s2.streak_count,
        current_streak_days=s2.streak_days,
        current_streak_started_at=s2.streak_started_at,
        duration_days=30,
        now=grace_now,
    )
    assert s3.streak_count == 3
    assert s3.streak_days == 90
    assert s3.streak_started_at == now

    # Renewal after 5 days lapsed (beyond 24h grace) -> resets streak to 1
    lapsed_now = s3.new_expires_at + timedelta(days=5)
    s4 = calculate_membership_streak(
        current_expires_at=s3.new_expires_at,
        current_streak_count=s3.streak_count,
        current_streak_days=s3.streak_days,
        current_streak_started_at=s3.streak_started_at,
        duration_days=30,
        now=lapsed_now,
    )
    assert s4.streak_count == 1
    assert s4.streak_days == 30
    assert s4.streak_started_at == lapsed_now


def test_build_fandom_leaderboard_response_sorting_and_caller_lookup():
    """Verifies pure sorting and rank assignment for both Spending and Streak leaderboard tabs."""
    fandom_id = uuid.uuid4()
    u1_id = uuid.uuid4()
    u2_id = uuid.uuid4()
    now = datetime.now(timezone.utc)

    raw_spending = [
        {
            "user_id": u1_id,
            "username": "fan_streak",
            "display_name": "Fan Bền Bỉ",
            "avatar_url": None,
            "total_spent_vnd": 100_000,
            "paid_orders_count": 2,
            "highest_tier_name": "Hội viên Bạc",
            "highest_tier_level": 1,
            "highest_tier_color_hex": "#C0C0C0",
        },
        {
            "user_id": u2_id,
            "username": "fan_whale",
            "display_name": "Đại Gia Fandom",
            "avatar_url": None,
            "total_spent_vnd": 300_000,
            "paid_orders_count": 1,
            "highest_tier_name": "Hội viên Kim Cương",
            "highest_tier_level": 4,
            "highest_tier_color_hex": "#FFD700",
        },
    ]
    raw_streaks = [
        {
            "user_id": u2_id,
            "username": "fan_whale",
            "display_name": "Đại Gia Fandom",
            "avatar_url": None,
            "streak_count": 1,
            "streak_days": 30,
            "tier_name": "Hội viên Kim Cương",
            "tier_level": 4,
            "tier_color_hex": "#FFD700",
            "streak_started_at": now,
            "expires_at": now + timedelta(days=30),
            "is_active": True,
        },
        {
            "user_id": u1_id,
            "username": "fan_streak",
            "display_name": "Fan Bền Bỉ",
            "avatar_url": None,
            "streak_count": 3,
            "streak_days": 90,
            "tier_name": "Hội viên Bạc",
            "tier_level": 1,
            "tier_color_hex": "#C0C0C0",
            "streak_started_at": now - timedelta(days=60),
            "expires_at": now + timedelta(days=30),
            "is_active": True,
        },
    ]

    lb = build_fandom_leaderboard_response(
        fandom_id=fandom_id,
        raw_spending=raw_spending,
        raw_streaks=raw_streaks,
        current_user_id=u1_id,
        limit=10,
    )

    assert len(lb.spending_leaderboard) == 2
    assert lb.spending_leaderboard[0].user_id == u2_id
    assert lb.spending_leaderboard[0].rank == 1
    assert lb.spending_leaderboard[0].total_spent_vnd == 300_000
    assert lb.spending_leaderboard[1].user_id == u1_id
    assert lb.spending_leaderboard[1].rank == 2

    assert len(lb.streak_leaderboard) == 2
    assert lb.streak_leaderboard[0].user_id == u1_id
    assert lb.streak_leaderboard[0].rank == 1
    assert lb.streak_leaderboard[0].streak_count == 3
    assert lb.streak_leaderboard[0].streak_days == 90
    assert lb.streak_leaderboard[1].user_id == u2_id
    assert lb.streak_leaderboard[1].rank == 2

    assert lb.my_spending_entry is not None
    assert lb.my_spending_entry.rank == 2
    assert lb.my_streak_entry is not None
    assert lb.my_streak_entry.rank == 1

