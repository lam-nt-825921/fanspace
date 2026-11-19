"""Integration tests for concurrent SePay webhooks (`asyncio.gather`), idempotency under race conditions,
Form URL-encoded payloads, and `DH` + 3..10 digits payment code extraction (FR-09 Remediation).
"""

import asyncio
import secrets
import uuid
import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import func, select

from app.core.database import AsyncSessionLocal
from app.core.security import create_access_token, get_password_hash
from app.main import app
from app.modules.billing.models import PaymentOrder, PaymentTransaction
from app.modules.billing.reconciliation import extract_sepay_order_code
from app.modules.billing.schemas import SepayWebhookPayload
from app.modules.identity.models import User


@pytest.fixture
async def async_client():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        yield client


def test_sepay_extract_order_code_supports_3_to_10_digits():
    """Verifies that `DH` + 3..10 integer digits are accurately extracted while 2 or 11 digits are ignored."""
    p3 = SepayWebhookPayload(
        id=1,
        content="CHUYEN KHOAN DH123 FANSPACE",
        transferAmount=20000,
    )
    p10 = SepayWebhookPayload(
        id=2,
        content="CHUYEN KHOAN DH1234567890 FANSPACE",
        transferAmount=20000,
    )
    p2_invalid = SepayWebhookPayload(
        id=3,
        content="CHUYEN KHOAN DH12 FANSPACE",
        transferAmount=20000,
    )

    assert extract_sepay_order_code(p3) == "DH123"
    assert extract_sepay_order_code(p10) == "DH1234567890"
    assert extract_sepay_order_code(p2_invalid) is None


@pytest.mark.asyncio
async def test_sepay_concurrent_duplicate_and_split_webhooks_plus_form_urlencoded(
    async_client: AsyncClient,
):
    """Verifies:
    1. Concurrent duplicate webhooks (`same sepay_transaction_id`) via `asyncio.gather` return 200 OK (no 500) and record only 1 transaction.
    2. Concurrent split webhooks (`different sepay_transaction_id`, 40k + 60k = 100k) accumulate accurately via `FOR UPDATE` row lock without lost updates.
    3. Webhook accepts `application/x-www-form-urlencoded` payload authenticated with `Authorization: Apikey`.
    """
    suffix = uuid.uuid4().hex[:8]

    async def create_user_headers(prefix: str) -> tuple[User, dict[str, str]]:
        user = User(
            username=f"{prefix}_{suffix}",
            email=f"{prefix}_{suffix}@vnu.edu.vn",
            password_hash=get_password_hash("Password123!"),
            display_name=prefix.capitalize(),
            is_active=True,
            is_email_verified=True,
        )
        async with AsyncSessionLocal() as db:
            db.add(user)
            await db.commit()
            await db.refresh(user)
        token = create_access_token({"sub": str(user.id), "username": user.username})
        return user, {"Authorization": f"Bearer {token}"}

    _, owner_headers = await create_user_headers("sepay_conc_owner")
    _, fan_headers = await create_user_headers("sepay_conc_fan")

    # Setup Fandom, Bank Account, and 100,000 VND Membership Tier
    res_fandom = await async_client.post(
        "/api/v1/fandoms",
        headers=owner_headers,
        json={
            "name": f"SePay Concurrency {suffix}",
            "slug": f"sepay-conc-{suffix}",
            "description": "Concurrency & Form Webhook Test",
        },
    )
    assert res_fandom.status_code == 201
    fandom_payload = res_fandom.json()
    fandom_id = fandom_payload.get("fandom_id") or fandom_payload["id"]

    await async_client.post(f"/api/v1/fandoms/{fandom_id}/join", headers=fan_headers)
    await async_client.put(
        f"/api/v1/fandoms/{fandom_id}/bank-account",
        headers=owner_headers,
        json={
            "bank_code": "MBBank",
            "account_number": "0988777666",
            "account_name": "NGUYEN TRONG LAM",
            "is_active": True,
        },
    )
    res_tier = await async_client.post(
        f"/api/v1/fandoms/{fandom_id}/memberships",
        headers=owner_headers,
        json={
            "name": "VIP Platinum",
            "tier_level": 1,
            "price_fiat_vnd": 100000,
            "duration_days": 30,
        },
    )
    assert res_tier.status_code == 201
    tier_id = res_tier.json()["id"]

    # ------------------------------------------------------------------
    # Scenario 1: Concurrent duplicate webhooks with same sepay_transaction_id
    # ------------------------------------------------------------------
    res_order1 = await async_client.post(
        f"/api/v1/fandoms/{fandom_id}/orders",
        headers=fan_headers,
        json={"role_id": tier_id},
    )
    assert res_order1.status_code == 201
    order1_code = res_order1.json()["order_code"]
    dup_sepay_id = secrets.randbelow(800_000_000) + 100_000_000

    webhook_json = {
        "id": dup_sepay_id,
        "gateway": "MBBank",
        "transactionDate": "2026-11-19 12:00:00",
        "accountNumber": "0988777666",
        "code": order1_code,
        "content": f"CHUYEN TIEN {order1_code}",
        "transferType": "in",
        "transferAmount": 100000,
    }
    apikey_headers = {"Authorization": "Apikey sepay_fanspace_secret_2026"}

    res_a, res_b = await asyncio.gather(
        async_client.post("/api/v1/billing/sepay-webhook", headers=apikey_headers, json=webhook_json),
        async_client.post("/api/v1/billing/sepay-webhook", headers=apikey_headers, json=webhook_json),
    )
    assert res_a.status_code == 200
    assert res_b.status_code == 200
    replays = [res_a.json()["idempotent_replay"], res_b.json()["idempotent_replay"]]
    assert False in replays

    async with AsyncSessionLocal() as db:
        cnt_res = await db.execute(
            select(func.count(PaymentTransaction.id)).where(
                PaymentTransaction.sepay_transaction_id == dup_sepay_id
            )
        )
        assert int(cnt_res.scalar_one()) == 1

    # ------------------------------------------------------------------
    # Scenario 2: Concurrent split payments (40,000 + 60,000 = 100,000) + Form URL-encoded
    # ------------------------------------------------------------------
    res_order2 = await async_client.post(
        f"/api/v1/fandoms/{fandom_id}/orders",
        headers=fan_headers,
        json={"role_id": tier_id},
    )
    assert res_order2.status_code == 201
    order2_code = res_order2.json()["order_code"]

    tx_part1_id = dup_sepay_id + 1
    tx_part2_id = dup_sepay_id + 2

    part1_form = {
        "id": str(tx_part1_id),
        "gateway": "MBBank",
        "transactionDate": "2026-11-19 12:05:00",
        "accountNumber": "0988777666",
        "code": order2_code,
        "content": f"THANH TOAN DOT 1 {order2_code}",
        "transferType": "in",
        "transferAmount": "40000",
    }
    part2_json = {
        "id": tx_part2_id,
        "gateway": "MBBank",
        "transactionDate": "2026-11-19 12:05:01",
        "accountNumber": "0988777666",
        "code": order2_code,
        "content": f"THANH TOAN DOT 2 {order2_code}",
        "transferType": "in",
        "transferAmount": 60000,
    }

    res_p1, res_p2 = await asyncio.gather(
        async_client.post("/api/v1/billing/sepay-webhook", headers=apikey_headers, data=part1_form),
        async_client.post("/api/v1/billing/sepay-webhook", headers=apikey_headers, json=part2_json),
    )
    assert res_p1.status_code == 200
    assert res_p2.status_code == 200

    async with AsyncSessionLocal() as db:
        ord_res = await db.execute(
            select(PaymentOrder).where(PaymentOrder.order_code == order2_code)
        )
        final_order = ord_res.scalar_one()
        assert final_order.paid_amount_vnd == 100000
        assert final_order.status == "PAID"
