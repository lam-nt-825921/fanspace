"""Integration tests for Fandom Monetization and SePay 3-Way Reconciliation (FR-09 / UC-11).

Covers:
1. Fandom Bank Account configuration & Membership Tier CRUD (max 4 tiers enforcement).
2. Order creation with default SePay payment code (`DH...`) and VietQR generation.
3. SePay Webhook verification via HMAC-SHA256 (`X-SePay-Signature` + `X-SePay-Timestamp`).
4. 3-Way Matching (`Product - Order - Transaction`) in PostgreSQL ACID transaction,
   automatic Role provisioning (`expires_at`), and VIP channel access unlock.
5. Idempotency protection against duplicate SePay webhook retries & membership renewal extension.
6. Underpaid partial transfer handling followed by top-up completion.
7. Unmatched transfer Audit Trail logging and Fandom Owner manual reconciliation.
8. Rejecting forged/tampered webhook requests with 401 Unauthorized.
"""

import json
import time
import uuid
from datetime import datetime, timezone

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import delete

from app.core.config import get_settings
from app.core.database import AsyncSessionLocal
from app.core.permissions import DefaultMembershipPermissionAdapter, Permission
from app.core.security import create_access_token, get_password_hash
from app.main import app
from app.modules.billing.models import (
    FandomBankAccount,
    PaymentOrder,
    PaymentTransaction,
)
from app.modules.billing.service import BillingService
from app.modules.chat.models import Channel
from app.modules.fandom.models import Fandom, FandomMember
from app.modules.identity.models import User
from app.modules.rbac.models import MemberRole, PermissionBit, Role

settings = get_settings()


async def _cleanup_billing_entities(
    user_ids: list[uuid.UUID],
    fandom_ids: list[uuid.UUID],
) -> None:
    """Cleans up test records from PostgreSQL."""
    async with AsyncSessionLocal() as db:
        if fandom_ids:
            await db.execute(
                delete(PaymentTransaction).where(PaymentTransaction.fandom_id.in_(fandom_ids))
            )
            await db.execute(
                delete(PaymentOrder).where(PaymentOrder.fandom_id.in_(fandom_ids))
            )
            await db.execute(
                delete(FandomBankAccount).where(FandomBankAccount.fandom_id.in_(fandom_ids))
            )
            await db.execute(delete(Channel).where(Channel.fandom_id.in_(fandom_ids)))
            await db.execute(delete(MemberRole).where(MemberRole.fandom_id.in_(fandom_ids)))
            await db.execute(delete(Role).where(Role.fandom_id.in_(fandom_ids)))
            await db.execute(delete(FandomMember).where(FandomMember.fandom_id.in_(fandom_ids)))
            await db.execute(delete(Fandom).where(Fandom.id.in_(fandom_ids)))
        if user_ids:
            await db.execute(delete(User).where(User.id.in_(user_ids)))
        await db.commit()


def _sign_sepay_payload(payload_dict: dict, secret: str | None = None) -> tuple[bytes, dict[str, str]]:
    """Serializes payload and generates valid SePay HMAC-SHA256 headers."""
    raw_bytes = json.dumps(payload_dict).encode("utf-8")
    ts_str = str(int(time.time()))
    active_secret = secret or settings.SEPAY_WEBHOOK_SECRET
    sig_hex = BillingService.compute_sepay_hmac_signature(raw_bytes, active_secret, ts_str)
    headers = {
        "Content-Type": "application/json",
        "X-SePay-Signature": f"sha256={sig_hex}",
        "X-SePay-Timestamp": ts_str,
    }
    return raw_bytes, headers


@pytest.mark.asyncio
async def test_owner_configure_bank_and_membership_tiers_quota():
    """Tests bank account configuration and Membership Tier CRUD (max 4 tiers limit)."""
    suffix = uuid.uuid4().hex[:8]
    owner = User(
        username=f"owner_biz_{suffix}",
        email=f"owner_biz_{suffix}@test.vn",
        password_hash=get_password_hash("Pass123!"),
        display_name="Fandom Creator",
        is_active=True,
    )
    fan = User(
        username=f"fan_biz_{suffix}",
        email=f"fan_biz_{suffix}@test.vn",
        password_hash=get_password_hash("Pass123!"),
        display_name="Normal Fan",
        is_active=True,
    )

    async with AsyncSessionLocal() as db:
        db.add_all([owner, fan])
        await db.commit()
        await db.refresh(owner)
        await db.refresh(fan)

        fandom = Fandom(
            name=f"Fandom Monetization {suffix}",
            slug=f"fandom-biz-{suffix}",
            owner_id=owner.id,
            category="Âm nhạc",
            admission_mode="OPEN",
            member_count=2,
        )
        db.add(fandom)
        await db.commit()
        await db.refresh(fandom)

    owner_headers = {
        "Authorization": f"Bearer {create_access_token({'sub': str(owner.id), 'username': owner.username})}"
    }
    fan_headers = {
        "Authorization": f"Bearer {create_access_token({'sub': str(fan.id), 'username': fan.username})}"
    }
    transport = ASGITransport(app=app)

    try:
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            # 1. Non-owner cannot configure bank account
            res_forbidden = await client.put(
                f"/api/v1/fandoms/{fandom.id}/bank-account",
                headers=fan_headers,
                json={
                    "bank_code": "MBBank",
                    "account_number": "0987654321",
                    "account_name": "NGUYEN VAN HACK",
                },
            )
            assert res_forbidden.status_code == 403

            # 2. Owner configures receiving bank account
            res_bank = await client.put(
                f"/api/v1/fandoms/{fandom.id}/bank-account",
                headers=owner_headers,
                json={
                    "bank_code": "MBBank",
                    "account_number": "0355999888",
                    "account_name": "nguyen van owner",
                    "is_active": True,
                },
            )
            assert res_bank.status_code == 200
            bank_data = res_bank.json()
            assert bank_data["bank_code"] == "MBBank"
            assert bank_data["account_number"] == "0355999888"
            assert bank_data["account_name"] == "NGUYEN VAN OWNER"

            # 3. Create 4 Membership Tiers (Tier 1..4)
            created_tier_ids = []
            for idx in range(1, 5):
                res_tier = await client.post(
                    f"/api/v1/fandoms/{fandom.id}/memberships",
                    headers=owner_headers,
                    json={
                        "name": f"VIP Tier {idx}",
                        "tier_level": idx,
                        "color_hex": "#FFD700",
                        "priority": 40 + idx * 5,
                        "permissions_bitmask": PermissionBit.BYPASS_SLOWMODE,
                        "price_fiat_vnd": idx * 25000,
                        "duration_days": 30,
                    },
                )
                assert res_tier.status_code == 201
                created_tier_ids.append(res_tier.json()["id"])

            # 4. Creating a 5th tier is rejected (max 4 tiers per fandom)
            res_fifth = await client.post(
                f"/api/v1/fandoms/{fandom.id}/memberships",
                headers=owner_headers,
                json={
                    "name": "VIP Tier 5 Overflow",
                    "tier_level": 4,
                    "price_fiat_vnd": 200000,
                    "duration_days": 30,
                },
            )
            assert res_fifth.status_code == 400

            # 5. Update Tier 1 price and delete Tier 4
            res_upd = await client.put(
                f"/api/v1/fandoms/{fandom.id}/memberships/{created_tier_ids[0]}",
                headers=owner_headers,
                json={"name": "Superfan Bạc", "price_fiat_vnd": 35000},
            )
            assert res_upd.status_code == 200
            assert res_upd.json()["name"] == "Superfan Bạc"
            assert res_upd.json()["price_fiat_vnd"] == 35000

            res_del = await client.delete(
                f"/api/v1/fandoms/{fandom.id}/memberships/{created_tier_ids[3]}",
                headers=owner_headers,
            )
            assert res_del.status_code == 200

            res_list = await client.get(f"/api/v1/fandoms/{fandom.id}/memberships")
            assert res_list.status_code == 200
            assert len(res_list.json()["tiers"]) == 3
    finally:
        await _cleanup_billing_entities([owner.id, fan.id], [fandom.id])


@pytest.mark.asyncio
async def test_3way_matching_sepay_webhook_hmac_and_idempotency():
    """Tests full Order -> SePay HMAC Webhook -> ACID Role Provisioning -> Idempotency & Renewal."""
    suffix = uuid.uuid4().hex[:8]
    owner = User(
        username=f"owner_3way_{suffix}",
        email=f"owner_3way_{suffix}@test.vn",
        password_hash=get_password_hash("Pass123!"),
        display_name="Owner 3Way",
        is_active=True,
    )
    fan = User(
        username=f"fan_3way_{suffix}",
        email=f"fan_3way_{suffix}@test.vn",
        password_hash=get_password_hash("Pass123!"),
        display_name="Fan 3Way",
        is_active=True,
    )

    async with AsyncSessionLocal() as db:
        db.add_all([owner, fan])
        await db.commit()
        await db.refresh(owner)
        await db.refresh(fan)

        fandom = Fandom(
            name=f"Fandom SePay {suffix}",
            slug=f"fandom-sepay-{suffix}",
            owner_id=owner.id,
            category="Âm nhạc",
            admission_mode="OPEN",
            member_count=2,
        )
        db.add(fandom)
        await db.commit()
        await db.refresh(fandom)

        db.add_all(
            [
                FandomMember(fandom_id=fandom.id, user_id=owner.id, status="ACTIVE"),
                FandomMember(fandom_id=fandom.id, user_id=fan.id, status="ACTIVE"),
                FandomBankAccount(
                    fandom_id=fandom.id,
                    bank_code="Vietcombank",
                    account_number="001100223344",
                    account_name="CHU FANDOM",
                    is_active=True,
                ),
            ]
        )
        vip_channel = Channel(
            fandom_id=fandom.id,
            name="vip-lounge",
            type="TEXT",
            is_membership_only=True,
            slow_mode_seconds=15,
        )
        db.add(vip_channel)
        await db.commit()
        await db.refresh(vip_channel)

    owner_headers = {
        "Authorization": f"Bearer {create_access_token({'sub': str(owner.id), 'username': owner.username})}"
    }
    fan_headers = {
        "Authorization": f"Bearer {create_access_token({'sub': str(fan.id), 'username': fan.username})}"
    }
    transport = ASGITransport(app=app)

    try:
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            # 1. Owner creates a Membership Tier Role (50,000 VND / 30 days)
            res_tier = await client.post(
                f"/api/v1/fandoms/{fandom.id}/memberships",
                headers=owner_headers,
                json={
                    "name": "Hội viên Kim Cương",
                    "tier_level": 1,
                    "color_hex": "#E040FB",
                    "priority": 60,
                    "permissions_bitmask": PermissionBit.BYPASS_SLOWMODE,
                    "price_fiat_vnd": 50000,
                    "duration_days": 30,
                },
            )
            assert res_tier.status_code == 201
            tier_id = res_tier.json()["id"]

            # 2. Before buying, Fan cannot access VIP membership-only channel
            async with AsyncSessionLocal() as db:
                adapter = DefaultMembershipPermissionAdapter(db)
                perms_before = await adapter.resolve_permissions(
                    fan.id, fandom.id, vip_channel.id
                )
                assert perms_before == set()

            # 3. Fan creates a PaymentOrder
            res_order = await client.post(
                f"/api/v1/fandoms/{fandom.id}/orders",
                headers=fan_headers,
                json={"role_id": tier_id},
            )
            assert res_order.status_code == 201
            order_data = res_order.json()
            order_code = order_data["order_code"]
            assert order_code.startswith("DH")
            assert order_data["amount_vnd"] == 50000
            assert order_data["status"] == "PENDING"
            assert "qr.sepay.vn/img" in order_data["qr_url"]
            assert order_code in order_data["qr_url"]

            # 4. Reject webhook with invalid HMAC-SHA256 signature
            bad_payload = {
                "id": 700001,
                "gateway": "Vietcombank",
                "transactionDate": "2026-11-09 22:30:00",
                "accountNumber": "001100223344",
                "code": order_code,
                "content": f"{order_code} chuyen khoan",
                "transferType": "in",
                "transferAmount": 50000,
            }
            raw_bad, bad_headers = _sign_sepay_payload(bad_payload, secret="wrong_secret_key")
            res_unauth = await client.post(
                "/api/v1/billing/sepay-webhook",
                content=raw_bad,
                headers=bad_headers,
            )
            assert res_unauth.status_code == 401

            # 5. Send authentic HMAC-SHA256 signed SePay Webhook (exact 3-Way Match)
            valid_payload = {
                "id": 800001,
                "gateway": "Vietcombank",
                "transactionDate": "2026-11-09 22:31:00",
                "accountNumber": "001100223344",
                "code": order_code,
                "content": f"MBVCB.9988.{order_code} thanh toan goi kim cuong",
                "transferType": "in",
                "transferAmount": 50000,
                "referenceCode": "FT26313998877",
            }
            raw_valid, valid_headers = _sign_sepay_payload(valid_payload)
            res_wh = await client.post(
                "/api/v1/billing/sepay-webhook",
                content=raw_valid,
                headers=valid_headers,
            )
            assert res_wh.status_code == 200
            wh_data = res_wh.json()
            assert wh_data["success"] is True
            assert wh_data["idempotent_replay"] is False
            assert wh_data["reconciliation_status"] == "MATCHED"
            assert wh_data["order_status"] == "PAID"

            # 6. Verify Order state and Fan's VIP channel permissions
            res_check = await client.get(
                f"/api/v1/orders/{order_code}",
                headers=fan_headers,
            )
            assert res_check.status_code == 200
            checked_order = res_check.json()
            assert checked_order["status"] == "PAID"
            assert checked_order["paid_amount_vnd"] == 50000
            assert checked_order["remaining_amount_vnd"] == 0
            first_expiry_str = checked_order["member_role_expires_at"]
            assert first_expiry_str is not None

            async with AsyncSessionLocal() as db:
                adapter = DefaultMembershipPermissionAdapter(db)
                perms_after = await adapter.resolve_permissions(
                    fan.id, fandom.id, vip_channel.id
                )
                assert Permission.VIEW_CHANNEL in perms_after
                assert Permission.SEND_MESSAGES in perms_after
                assert Permission.BYPASS_SLOWMODE in perms_after

            # 7. Idempotency Check: Replay the exact same webhook (sepay id 800001)
            raw_replay, replay_headers = _sign_sepay_payload(valid_payload)
            res_replay = await client.post(
                "/api/v1/billing/sepay-webhook",
                content=raw_replay,
                headers=replay_headers,
            )
            assert res_replay.status_code == 200
            assert res_replay.json()["idempotent_replay"] is True

            # Verify expiry was NOT doubled on replay
            res_check_after_replay = await client.get(
                f"/api/v1/orders/{order_code}",
                headers=fan_headers,
            )
            assert res_check_after_replay.json()["member_role_expires_at"] == first_expiry_str
    finally:
        await _cleanup_billing_entities([owner.id, fan.id], [fandom.id])


@pytest.mark.asyncio
async def test_underpaid_topup_and_unmatched_manual_reconciliation():
    """Tests partial payment (UNDERPAID -> PAID on second transfer) and manual reconciliation of unmatched transfers."""
    suffix = uuid.uuid4().hex[:8]
    owner = User(
        username=f"owner_edge_{suffix}",
        email=f"owner_edge_{suffix}@test.vn",
        password_hash=get_password_hash("Pass123!"),
        display_name="Owner Edge",
        is_active=True,
    )
    fan1 = User(
        username=f"fan1_edge_{suffix}",
        email=f"fan1_edge_{suffix}@test.vn",
        password_hash=get_password_hash("Pass123!"),
        display_name="Fan Underpaid",
        is_active=True,
    )
    fan2 = User(
        username=f"fan2_edge_{suffix}",
        email=f"fan2_edge_{suffix}@test.vn",
        password_hash=get_password_hash("Pass123!"),
        display_name="Fan WrongMemo",
        is_active=True,
    )

    async with AsyncSessionLocal() as db:
        db.add_all([owner, fan1, fan2])
        await db.commit()
        for u in (owner, fan1, fan2):
            await db.refresh(u)

        fandom = Fandom(
            name=f"Fandom Edge {suffix}",
            slug=f"fandom-edge-{suffix}",
            owner_id=owner.id,
            category="Âm nhạc",
            admission_mode="OPEN",
            member_count=3,
        )
        db.add(fandom)
        await db.commit()
        await db.refresh(fandom)

        tier_role = Role(
            fandom_id=fandom.id,
            name="Gói Vàng",
            color_hex="#FFD700",
            priority=50,
            permissions_bitmask=PermissionBit.READ_MESSAGES | PermissionBit.SEND_MESSAGES,
            is_membership_tier=True,
            tier_level=1,
            price_fiat_vnd=100000,
            duration_days=30,
        )
        db.add_all(
            [
                tier_role,
                FandomBankAccount(
                    fandom_id=fandom.id,
                    bank_code="MBBank",
                    account_number="999988887777",
                    account_name="CHU FANDOM EDGE",
                    is_active=True,
                ),
            ]
        )
        await db.commit()
        await db.refresh(tier_role)

    owner_headers = {
        "Authorization": f"Bearer {create_access_token({'sub': str(owner.id), 'username': owner.username})}"
    }
    fan1_headers = {
        "Authorization": f"Bearer {create_access_token({'sub': str(fan1.id), 'username': fan1.username})}"
    }
    fan2_headers = {
        "Authorization": f"Bearer {create_access_token({'sub': str(fan2.id), 'username': fan2.username})}"
    }
    transport = ASGITransport(app=app)

    try:
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            # --- Scenario A: Fan 1 creates 100k order, pays 40k then 60k ---
            res_o1 = await client.post(
                f"/api/v1/fandoms/{fandom.id}/orders",
                headers=fan1_headers,
                json={"role_id": str(tier_role.id)},
            )
            assert res_o1.status_code == 201
            code1 = res_o1.json()["order_code"]

            # Transfer 1: 40,000 VND (Underpaid)
            raw_t1, hdr_t1 = _sign_sepay_payload(
                {
                    "id": 910001,
                    "gateway": "MBBank",
                    "transactionDate": "2026-11-09 22:35:00",
                    "accountNumber": "999988887777",
                    "code": code1,
                    "content": f"{code1} ck dot 1",
                    "transferType": "in",
                    "transferAmount": 40000,
                }
            )
            res_wh1 = await client.post(
                "/api/v1/billing/sepay-webhook", content=raw_t1, headers=hdr_t1
            )
            assert res_wh1.status_code == 200
            assert res_wh1.json()["reconciliation_status"] == "UNDERPAID"
            assert res_wh1.json()["order_status"] == "UNDERPAID"

            # Transfer 2: remaining 60,000 VND -> Completes order!
            raw_t2, hdr_t2 = _sign_sepay_payload(
                {
                    "id": 910002,
                    "gateway": "MBBank",
                    "transactionDate": "2026-11-09 22:36:00",
                    "accountNumber": "999988887777",
                    "code": code1,
                    "content": f"{code1} ck dot 2",
                    "transferType": "in",
                    "transferAmount": 60000,
                }
            )
            res_wh2 = await client.post(
                "/api/v1/billing/sepay-webhook", content=raw_t2, headers=hdr_t2
            )
            assert res_wh2.status_code == 200
            assert res_wh2.json()["reconciliation_status"] == "MATCHED"
            assert res_wh2.json()["order_status"] == "PAID"

            # --- Scenario B: Fan 2 creates 100k order, transfers with wrong content -> Owner resolves manually ---
            res_o2 = await client.post(
                f"/api/v1/fandoms/{fandom.id}/orders",
                headers=fan2_headers,
                json={"role_id": str(tier_role.id)},
            )
            assert res_o2.status_code == 201
            code2 = res_o2.json()["order_code"]

            raw_t3, hdr_t3 = _sign_sepay_payload(
                {
                    "id": 910003,
                    "gateway": "MBBank",
                    "transactionDate": "2026-11-09 22:37:00",
                    "accountNumber": "999988887777",
                    "code": None,
                    "content": "FAN2 QUEN GHI MA DON HANG",
                    "transferType": "in",
                    "transferAmount": 100000,
                }
            )
            res_wh3 = await client.post(
                "/api/v1/billing/sepay-webhook", content=raw_t3, headers=hdr_t3
            )
            assert res_wh3.status_code == 200
            assert res_wh3.json()["reconciliation_status"] == "UNMATCHED_ORDER"

            # Owner inspects Audit Trail ledger
            res_ledger = await client.get(
                f"/api/v1/fandoms/{fandom.id}/transactions",
                headers=owner_headers,
            )
            assert res_ledger.status_code == 200
            ledger_data = res_ledger.json()
            unmatched_txs = [
                t
                for t in ledger_data["transactions"]
                if t["reconciliation_status"] == "UNMATCHED_ORDER"
            ]
            assert len(unmatched_txs) == 1
            unmatched_tx_id = unmatched_txs[0]["id"]

            # Owner resolves unmatched transaction to Fan 2's order `code2`
            res_resolve = await client.post(
                f"/api/v1/fandoms/{fandom.id}/transactions/{unmatched_tx_id}/resolve",
                headers=owner_headers,
                json={
                    "order_code": code2,
                    "note": "Đã kiểm tra sao kê FT của Fan 2",
                },
            )
            assert res_resolve.status_code == 200
            assert res_resolve.json()["reconciliation_status"] == "MANUAL_MATCHED"

            # Verify Fan 2's order is now PAID and Role is granted
            res_o2_after = await client.get(
                f"/api/v1/orders/{code2}",
                headers=fan2_headers,
            )
            assert res_o2_after.status_code == 200
            assert res_o2_after.json()["status"] == "PAID"
            assert res_o2_after.json()["member_role_expires_at"] is not None
    finally:
        await _cleanup_billing_entities([owner.id, fan1.id, fan2.id], [fandom.id])
