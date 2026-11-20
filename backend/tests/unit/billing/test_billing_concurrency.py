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
import uuid
from datetime import datetime, timezone
import pytest
from sqlalchemy import select

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
