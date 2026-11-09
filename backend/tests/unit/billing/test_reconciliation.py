"""Unit tests for pure domain calculations and 3-Way Matching in `reconciliation.py`."""

import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi import HTTPException

from app.modules.billing.models import PaymentOrder
from app.modules.billing.reconciliation import (
    build_sepay_qr_url,
    calculate_membership_expiry,
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
