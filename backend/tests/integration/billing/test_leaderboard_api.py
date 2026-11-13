"""Integration tests for Fandom Membership Leaderboard (Spending & Streak tabs)."""

import uuid
import pytest
from httpx import ASGITransport, AsyncClient

from app.core.security import create_access_token
from app.main import app
from app.core.database import AsyncSessionLocal
from app.modules.identity.models import User


async def _create_test_user(prefix: str, display_name: str) -> tuple[User, dict[str, str]]:
    """Creates a verified test user and returns `(user, auth_headers)`."""
    suffix = uuid.uuid4().hex[:8]
    async with AsyncSessionLocal() as db:
        user = User(
            email=f"{prefix}_{suffix}@example.com",
            username=f"{prefix}_{suffix}",
            display_name=display_name,
            password_hash="hashed_test_pw",
            is_email_verified=True,
            is_active=True,
        )
        db.add(user)
        await db.commit()
        await db.refresh(user)
    token = create_access_token(data={"sub": str(user.id), "platform": "WEB"})
    return user, {"Authorization": f"Bearer {token}"}


@pytest.mark.asyncio
async def test_fandom_leaderboard_spending_and_streak_tabs():
    """Verifies that GET /api/v1/fandoms/{identifier}/leaderboard returns accurate Spending and Streak rankings."""
    owner, owner_headers = await _create_test_user("lb_owner", "Chủ Fandom")
    fan_streak, streak_headers = await _create_test_user("lb_streak", "Fan Chuỗi Bền Bỉ")
    fan_whale, whale_headers = await _create_test_user("lb_whale", "Fan Đại Gia")

    slug = f"fandom-lb-{uuid.uuid4().hex[:8]}"

    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as client:
        # 1. Owner creates fandom
        res_fandom = await client.post(
            "/api/v1/fandoms",
            headers=owner_headers,
            json={
                "name": f"Fandom Leaderboard {slug}",
                "slug": slug,
                "category": "Music",
                "is_public": True,
                "admission_mode": "OPEN",
            },
        )
        assert res_fandom.status_code == 201

        # 2. Both fans join the fandom
        for hdr in (streak_headers, whale_headers):
            join_res = await client.post(
                f"/api/v1/fandoms/{slug}/join",
                headers=hdr,
            )
            assert join_res.status_code in (200, 201)

        # 3. Owner configures bank account and 2 Membership Tiers
        bank_res = await client.put(
            f"/api/v1/fandoms/{slug}/bank-account",
            headers=owner_headers,
            json={
                "bank_code": "MBBank",
                "account_number": "038999888777",
                "account_name": "CHU FANDOM VIP",
                "is_active": True,
            },
        )
        assert bank_res.status_code == 200

        t1_res = await client.post(
            f"/api/v1/fandoms/{slug}/memberships",
            headers=owner_headers,
            json={
                "name": "Hội viên Bạc",
                "tier_level": 1,
                "color_hex": "#42A5F5",
                "price_fiat_vnd": 40_000,
                "duration_days": 30,
            },
        )
        assert t1_res.status_code == 201
        tier1_id = t1_res.json()["id"]

        t2_res = await client.post(
            f"/api/v1/fandoms/{slug}/memberships",
            headers=owner_headers,
            json={
                "name": "Hội viên Vàng",
                "tier_level": 2,
                "color_hex": "#FFD700",
                "price_fiat_vnd": 150_000,
                "duration_days": 30,
            },
        )
        assert t2_res.status_code == 201
        tier2_id = t2_res.json()["id"]

        # 4. fan_streak purchases Tier 1 twice (2 consecutive periods: 80,000 VND total, streak_count = 2, streak_days = 60)
        for _ in range(2):
            order_res = await client.post(
                f"/api/v1/fandoms/{slug}/orders",
                headers=streak_headers,
                json={"role_id": tier1_id},
            )
            assert order_res.status_code == 201
            order_code = order_res.json()["order_code"]

            sim_res = await client.post(
                "/api/v1/billing/sepay-simulate",
                headers=owner_headers,
                json={"order_code": order_code},
            )
            assert sim_res.status_code == 200
            assert sim_res.json()["reconciliation_status"] == "MATCHED"

        # 5. fan_whale purchases Tier 2 once (150,000 VND total, streak_count = 1, streak_days = 30)
        whale_order = await client.post(
            f"/api/v1/fandoms/{slug}/orders",
            headers=whale_headers,
            json={"role_id": tier2_id},
        )
        assert whale_order.status_code == 201
        whale_code = whale_order.json()["order_code"]

        sim_whale = await client.post(
            "/api/v1/billing/sepay-simulate",
            headers=owner_headers,
            json={"order_code": whale_code},
        )
        assert sim_whale.status_code == 200

        # 6. Fetch Leaderboard as fan_streak
        lb_res = await client.get(
            f"/api/v1/fandoms/{slug}/leaderboard",
            headers=streak_headers,
        )
        assert lb_res.status_code == 200
        lb_data = lb_res.json()

        # Tab 1: Spending leaderboard -> fan_whale (#1: 150,000) > fan_streak (#2: 80,000)
        spending = lb_data["spending_leaderboard"]
        assert len(spending) == 2
        assert spending[0]["user_id"] == str(fan_whale.id)
        assert spending[0]["rank"] == 1
        assert spending[0]["total_spent_vnd"] == 150_000
        assert spending[0]["highest_tier_name"] == "Hội viên Vàng"

        assert spending[1]["user_id"] == str(fan_streak.id)
        assert spending[1]["rank"] == 2
        assert spending[1]["total_spent_vnd"] == 80_000
        assert spending[1]["paid_orders_count"] == 2

        # Tab 2: Streak leaderboard -> fan_streak (#1: streak_count=2, streak_days=60) > fan_whale (#2: streak_count=1, streak_days=30)
        streaks = lb_data["streak_leaderboard"]
        assert len(streaks) == 2
        assert streaks[0]["user_id"] == str(fan_streak.id)
        assert streaks[0]["rank"] == 1
        assert streaks[0]["streak_count"] == 2
        assert streaks[0]["streak_days"] == 60
        assert streaks[0]["tier_name"] == "Hội viên Bạc"

        assert streaks[1]["user_id"] == str(fan_whale.id)
        assert streaks[1]["rank"] == 2
        assert streaks[1]["streak_count"] == 1
        assert streaks[1]["streak_days"] == 30

        # Caller's personal rank entries
        assert lb_data["my_spending_entry"]["rank"] == 2
        assert lb_data["my_streak_entry"]["rank"] == 1
