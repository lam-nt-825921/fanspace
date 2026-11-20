"""Concurrency and Race Condition Verification Tests for Billing and Leaderboard.

Empirically tests concurrent execution scenarios:
1. Scenario A: 2 identical webhooks hitting the server at the exact same millisecond
   using `asyncio.gather`. Proves only 1 transaction is committed and the other returns
   an idempotent replay response without double-crediting money or VIP days.
2. Scenario B: Multiple distinct users paying simultaneously in a leaderboard race.
   Proves that concurrent transactions are committed independently without lost updates,
   and the resulting spending leaderboard reflects exact mathematical totals.
"""

import asyncio
import random
import uuid
from datetime import datetime, timedelta, timezone
import pytest
from sqlalchemy import func, select

from app.core.database import AsyncSessionLocal
from app.modules.billing.models import PaymentOrder, PaymentTransaction
from app.modules.billing.schemas import SepayWebhookPayload
from app.modules.billing.service import BillingService
from app.modules.fandom.models import Fandom, FandomMember
from app.modules.identity.models import User
from app.modules.rbac.models import Role


@pytest.mark.asyncio
async def test_concurrent_duplicate_webhooks_idempotency_race():
    """Proves that when 2 identical webhooks arrive concurrently, exactly 1 succeeds and 1 replays."""
    async with AsyncSessionLocal() as setup_db:
        test_suffix = uuid.uuid4().hex[:8]
        user = User(
            id=uuid.uuid4(),
            email=f"racer_{test_suffix}@test.com",
            username=f"racer_{test_suffix}",
            password_hash="argon2_hash",
            display_name=f"Racer {test_suffix}",
        )
        setup_db.add(user)
        await setup_db.flush()

        fandom = Fandom(
            id=uuid.uuid4(),
            name=f"Race Fandom {test_suffix}",
            slug=f"race-fandom-{test_suffix}",
            owner_id=user.id,
        )
        setup_db.add(fandom)
        await setup_db.flush()

        member = FandomMember(
            id=uuid.uuid4(),
            fandom_id=fandom.id,
            user_id=user.id,
            status="ACTIVE",
        )
        setup_db.add(member)

        role = Role(
            id=uuid.uuid4(),
            fandom_id=fandom.id,
            name="VIP Tier 1",
            is_membership_tier=True,
            tier_level=1,
            price_fiat_vnd=50_000,
            duration_days=30,
        )
        setup_db.add(role)
        await setup_db.flush()

        order_code = f"DH{uuid.uuid4().hex[:8].upper()}"
        order = PaymentOrder(
            id=uuid.uuid4(),
            order_code=order_code,
            user_id=user.id,
            fandom_id=fandom.id,
            role_id=role.id,
            role_name_snapshot="VIP Tier 1",
            amount_vnd=50_000,
            paid_amount_vnd=0,
            duration_days=30,
            bank_code="MBBank",
            account_number="6280793157",
            account_name="NGUYEN TUNG LAM",
            qr_url="https://qr.sepay.vn/test",
            status="PENDING",
            expires_at=datetime.now(timezone.utc),
        )
        setup_db.add(order)
        await setup_db.commit()

    # Create 2 identical webhook payloads with the exact same SePay transaction ID
    shared_sepay_id = int(f"99{uuid.uuid4().int % 10_000_000}")
    payload1 = SepayWebhookPayload(
        id=shared_sepay_id,
        gateway="MBBank",
        accountNumber="6280793157",
        code=order_code,
        content=f"Thanh toan {order_code}",
        transferType="in",
        transferAmount=50_000,
    )
    payload2 = SepayWebhookPayload(
        id=shared_sepay_id,
        gateway="MBBank",
        accountNumber="6280793157",
        code=order_code,
        content=f"Thanh toan {order_code}",
        transferType="in",
        transferAmount=50_000,
    )

    async def _send_hook(payload: SepayWebhookPayload):
        async with AsyncSessionLocal() as session:
            return await BillingService.process_sepay_webhook(session, payload)

    # Fire both webhooks simultaneously using asyncio.gather
    res1, res2 = await asyncio.gather(_send_hook(payload1), _send_hook(payload2))

    # Exactly one must be the primary processor, and the other must be an idempotent replay
    replays = [r for r in (res1, res2) if r.idempotent_replay is True]
    primaries = [r for r in (res1, res2) if r.idempotent_replay is False]

    assert len(primaries) == 1, "Exactly 1 webhook must process as primary"
    assert len(replays) == 1, "Exactly 1 webhook must be intercepted as idempotent replay"
    assert primaries[0].success is True
    assert replays[0].success is True

    # Verify database state has exactly 1 PaymentTransaction and order is PAID (not overpaid)
    async with AsyncSessionLocal() as verify_db:
        tx_res = await verify_db.execute(
            select(PaymentTransaction).where(
                PaymentTransaction.sepay_transaction_id == shared_sepay_id
            )
        )
        txs = list(tx_res.scalars().all())
        assert len(txs) == 1, "Database must store exactly 1 transaction record"

        order_res = await verify_db.execute(
            select(PaymentOrder).where(PaymentOrder.order_code == order_code)
        )
        updated_order = order_res.scalar_one()
        assert updated_order.status == "PAID"
        assert updated_order.paid_amount_vnd == 50_000, "Money must not be double-counted"


@pytest.mark.asyncio
async def test_concurrent_multiple_users_leaderboard_race():
    """Proves that multiple users paying concurrently all succeed without data loss and leaderboard is exact."""
    async with AsyncSessionLocal() as setup_db:
        test_suffix = uuid.uuid4().hex[:8]
        owner = User(
            id=uuid.uuid4(),
            email=f"owner_{test_suffix}@test.com",
            username=f"owner_{test_suffix}",
            password_hash="argon2",
            display_name=f"Owner {test_suffix}",
        )
        setup_db.add(owner)
        await setup_db.flush()

        fandom = Fandom(
            id=uuid.uuid4(),
            name=f"Leaderboard Fandom {test_suffix}",
            slug=f"lb-fandom-{test_suffix}",
            owner_id=owner.id,
        )
        setup_db.add(fandom)
        await setup_db.flush()

        role = Role(
            id=uuid.uuid4(),
            fandom_id=fandom.id,
            name="Diamond Fan",
            is_membership_tier=True,
            tier_level=3,
            price_fiat_vnd=100_000,
            duration_days=30,
        )
        setup_db.add(role)
        await setup_db.flush()

        # Create 3 users competing in a race with different payment amounts
        users = []
        amounts = [100_000, 200_000, 150_000]

        for i, amt in enumerate(amounts):
            u = User(
                id=uuid.uuid4(),
                email=f"racer_{i}_{test_suffix}@test.com",
                username=f"racer_{i}_{test_suffix}",
                password_hash="argon2",
                display_name=f"Racer {i} ({amt}k)",
            )
            setup_db.add(u)
            users.append(u)

        # Commit users first so foreign keys are established
        await setup_db.commit()

    async with AsyncSessionLocal() as setup_db2:
        orders = []
        for i, amt in enumerate(amounts):
            m = FandomMember(
                id=uuid.uuid4(),
                fandom_id=fandom.id,
                user_id=users[i].id,
                status="ACTIVE",
            )
            setup_db2.add(m)

            o_code = f"DH{uuid.uuid4().hex[:8].upper()}"
            o = PaymentOrder(
                id=uuid.uuid4(),
                order_code=o_code,
                user_id=users[i].id,
                fandom_id=fandom.id,
                role_id=role.id,
                role_name_snapshot="Diamond Fan",
                amount_vnd=amt,
                paid_amount_vnd=0,
                duration_days=30,
                bank_code="MBBank",
                account_number="6280793157",
                account_name="NGUYEN TUNG LAM",
                qr_url="https://qr.sepay.vn/test",
                status="PENDING",
                expires_at=datetime.now(timezone.utc),
            )
            setup_db2.add(o)
            orders.append(o)

        await setup_db2.commit()

    # Simultaneously execute webhooks for all 3 competing users
    async def _pay(order_obj: PaymentOrder, amount: int):
        hook_payload = SepayWebhookPayload(
            id=int(f"88{uuid.uuid4().int % 10_000_000}"),
            gateway="MBBank",
            accountNumber="6280793157",
            code=order_obj.order_code,
            content=f"Thanh toan {order_obj.order_code}",
            transferType="in",
            transferAmount=amount,
        )
        async with AsyncSessionLocal() as session:
            return await BillingService.process_sepay_webhook(session, hook_payload)

    results = await asyncio.gather(
        _pay(orders[0], amounts[0]),
        _pay(orders[1], amounts[1]),
        _pay(orders[2], amounts[2]),
    )

    for r in results:
        assert r.success is True
        assert r.reconciliation_status in ("MATCHED", "PAID")

    # Fetch and verify Leaderboard
    async with AsyncSessionLocal() as lb_db:
        lb = await BillingService.get_fandom_leaderboard(
            db=lb_db,
            identifier=str(fandom.id),
        )

        assert len(lb.spending_leaderboard) == 3
        # Rank 1: Racer 1 (200k)
        assert lb.spending_leaderboard[0].total_spent_vnd == 200_000
        assert lb.spending_leaderboard[0].rank == 1
        assert lb.spending_leaderboard[0].user_id == users[1].id

        # Rank 2: Racer 2 (150k)
        assert lb.spending_leaderboard[1].total_spent_vnd == 150_000
        assert lb.spending_leaderboard[1].rank == 2
        assert lb.spending_leaderboard[1].user_id == users[2].id

        # Rank 3: Racer 0 (100k)
        assert lb.spending_leaderboard[2].total_spent_vnd == 100_000
        assert lb.spending_leaderboard[2].rank == 3
        assert lb.spending_leaderboard[2].user_id == users[0].id


@pytest.mark.asyncio
async def test_high_concurrency_stress_150_webhooks_100_users_50_replays():
    """Stress tests high concurrency with 150 simultaneous webhooks across 100 distinct users.

    Simulates:
    - 100 distinct users each purchasing a VIP membership tier with varying amounts
      (50,000 VND to 149,000 VND).
    - 150 webhooks hitting the server at the exact same millisecond:
      * 100 unique webhooks corresponding to the 100 distinct orders.
      * 50 duplicate webhooks (replaying 50 transactions with identical payload & ID).
      * The 150 payloads are shuffled to interleave duplicates alongside primary requests.
    - Proves:
      1. Exactly 100 webhooks succeed as primary (idempotent_replay=False).
      2. Exactly 50 webhooks are safely intercepted as idempotent replays (idempotent_replay=True).
      3. Exactly 100 PaymentTransaction rows exist in the database (no duplicate records).
      4. All 100 orders transition to PAID with exact amounts (no double-counted money).
      5. The Spending Leaderboard contains exactly 100 ranked users in mathematically exact order.
    """
    test_suffix = uuid.uuid4().hex[:8]

    # 1. Setup Owner, Fandom, Role, and 100 distinct Users
    async with AsyncSessionLocal() as setup_db:
        owner = User(
            id=uuid.uuid4(),
            email=f"stress_owner_{test_suffix}@test.com",
            username=f"stress_owner_{test_suffix}",
            password_hash="argon2_hash",
            display_name=f"Stress Owner {test_suffix}",
        )
        setup_db.add(owner)
        await setup_db.flush()

        fandom = Fandom(
            id=uuid.uuid4(),
            name=f"Stress Fandom {test_suffix}",
            slug=f"stress-fandom-{test_suffix}",
            owner_id=owner.id,
        )
        setup_db.add(fandom)
        await setup_db.flush()

        role = Role(
            id=uuid.uuid4(),
            fandom_id=fandom.id,
            name="Stress VIP Tier",
            is_membership_tier=True,
            tier_level=1,
            price_fiat_vnd=50_000,
            duration_days=30,
        )
        setup_db.add(role)
        await setup_db.flush()

        # Batch create 100 users
        users: list[User] = []
        for i in range(100):
            u = User(
                id=uuid.uuid4(),
                email=f"stress_{test_suffix}_{i:03d}@test.com",
                username=f"stress_{test_suffix}_{i:03d}",
                password_hash="argon2_hash",
                display_name=f"Stress User {i:03d}",
            )
            setup_db.add(u)
            users.append(u)

        # Commit users first so foreign keys can be referenced
        await setup_db.commit()

    # 2. Setup 100 Fandom Members and 100 Payment Orders
    order_codes: list[str] = []
    amounts: list[int] = []
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=15)

    async with AsyncSessionLocal() as setup_db2:
        for i in range(100):
            member = FandomMember(
                id=uuid.uuid4(),
                fandom_id=fandom.id,
                user_id=users[i].id,
                status="ACTIVE",
            )
            setup_db2.add(member)

            # Amounts: 50,000 + i * 1,000 VND (50,000đ up to 149,000đ)
            amount = 50_000 + (i * 1_000)
            amounts.append(amount)
            o_code = f"DHSTRESS{test_suffix[:4].upper()}_{i:03d}"
            order_codes.append(o_code)

            order = PaymentOrder(
                id=uuid.uuid4(),
                order_code=o_code,
                user_id=users[i].id,
                fandom_id=fandom.id,
                role_id=role.id,
                role_name_snapshot="Stress VIP Tier",
                amount_vnd=amount,
                paid_amount_vnd=0,
                duration_days=30,
                bank_code="MBBank",
                account_number="6280793157",
                account_name="NGUYEN TUNG LAM",
                qr_url="https://qr.sepay.vn/test",
                status="PENDING",
                expires_at=expires_at,
            )
            setup_db2.add(order)

        await setup_db2.commit()

    # 3. Construct 100 Unique Webhook Payloads + 50 Duplicate Replay Payloads
    base_sepay_id = int(f"77{uuid.uuid4().int % 10_000_000}")

    primary_payloads: list[SepayWebhookPayload] = []
    for i in range(100):
        p = SepayWebhookPayload(
            id=base_sepay_id + i,
            gateway="MBBank",
            accountNumber="6280793157",
            code=order_codes[i],
            content=f"Thanh toan {order_codes[i]}",
            transferType="in",
            transferAmount=amounts[i],
        )
        primary_payloads.append(p)

    # Pick the first 50 payloads to duplicate
    duplicate_payloads: list[SepayWebhookPayload] = []
    for i in range(50):
        dup = SepayWebhookPayload(
            id=base_sepay_id + i,
            gateway="MBBank",
            accountNumber="6280793157",
            code=order_codes[i],
            content=f"Thanh toan {order_codes[i]}",
            transferType="in",
            transferAmount=amounts[i],
        )
        duplicate_payloads.append(dup)

    all_payloads = list(primary_payloads) + duplicate_payloads
    assert len(all_payloads) == 150

    # Shuffle the 150 payloads so replays are interleaved and race with originals
    random.seed(42)
    random.shuffle(all_payloads)

    # 4. Dispatch all 150 webhooks concurrently
    async def _send_webhook(payload: SepayWebhookPayload):
        async with AsyncSessionLocal() as session:
            return await BillingService.process_sepay_webhook(session, payload)

    results = await asyncio.gather(*[_send_webhook(p) for p in all_payloads])

    # 5. Verify In-Memory Webhook Results
    assert len(results) == 150
    for res in results:
        assert res.success is True, f"Webhook failed: {res.message}"

    primaries = [r for r in results if r.idempotent_replay is False]
    replays = [r for r in results if r.idempotent_replay is True]

    assert len(primaries) == 100, f"Expected 100 primary webhooks, got {len(primaries)}"
    assert len(replays) == 50, f"Expected 50 idempotent replays, got {len(replays)}"

    # 6. Verify Database Integrity & Leaderboard
    async with AsyncSessionLocal() as verify_db:
        # Check PaymentTransaction records: exactly 100 rows
        tx_count_res = await verify_db.execute(
            select(func.count(PaymentTransaction.id)).where(
                PaymentTransaction.sepay_transaction_id.between(
                    base_sepay_id, base_sepay_id + 99
                )
            )
        )
        tx_count = tx_count_res.scalar_one()
        assert tx_count == 100, f"Expected 100 transactions in DB, found {tx_count}"

        # Check PaymentOrders: all 100 must be PAID with exact amounts
        orders_res = await verify_db.execute(
            select(PaymentOrder).where(PaymentOrder.order_code.in_(order_codes))
        )
        verified_orders = list(orders_res.scalars().all())
        assert len(verified_orders) == 100
        for ord_obj in verified_orders:
            idx = int(ord_obj.order_code.split("_")[-1])
            assert ord_obj.status == "PAID", (
                f"Order {ord_obj.order_code} status is {ord_obj.status}"
            )
            assert ord_obj.paid_amount_vnd == amounts[idx], (
                f"Order {ord_obj.order_code} paid_amount={ord_obj.paid_amount_vnd} "
                f"!= expected {amounts[idx]}"
            )

        # Check Fandom Leaderboard: exactly 100 users, ordered descending by total_spent_vnd
        lb = await BillingService.get_fandom_leaderboard(
            db=verify_db,
            identifier=str(fandom.id),
            limit=100,
        )
        assert len(lb.spending_leaderboard) == 100, (
            f"Expected 100 users on leaderboard, got {len(lb.spending_leaderboard)}"
        )

        for rank_idx, entry in enumerate(lb.spending_leaderboard, start=1):
            expected_user_idx = 100 - rank_idx
            assert entry.rank == rank_idx
            assert entry.user_id == users[expected_user_idx].id
            assert entry.total_spent_vnd == amounts[expected_user_idx]
            assert entry.paid_orders_count == 1

        # Check Total Revenue on Leaderboard
        total_spent = sum(entry.total_spent_vnd for entry in lb.spending_leaderboard)
        assert total_spent == sum(amounts), (
            f"Total spent sum {total_spent} != {sum(amounts)}"
        )

