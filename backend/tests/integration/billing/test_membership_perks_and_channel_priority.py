"""Integration tests for separated Membership Perks and Channel Membership Priority (Phase 4)."""

import uuid
import pytest
from httpx import ASGITransport, AsyncClient

from app.core.database import AsyncSessionLocal
from app.core.security import create_access_token, get_password_hash
from app.main import app
from app.modules.identity.models import User
from app.modules.rbac.models import MembershipPerkBit


@pytest.fixture
async def async_client():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        yield client


@pytest.mark.asyncio
async def test_membership_perks_and_channel_priority_settings(
    async_client: AsyncClient,
):
    """Verifies separated MembershipPerkBit configuration and Channel min_tier / bypass_slowmode."""
    suffix = uuid.uuid4().hex[:8]

    async def create_user_headers(prefix: str) -> dict[str, str]:
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
        return {"Authorization": f"Bearer {token}"}

    owner_headers = await create_user_headers("owner_p4")
    tier1_headers = await create_user_headers("tier1_p4")
    tier2_headers = await create_user_headers("tier2_p4")
    free_headers = await create_user_headers("free_p4")

    # 1. Owner creates Fandom & configures Bank
    res_fandom = await async_client.post(
        "/api/v1/fandoms",
        headers=owner_headers,
        json={
            "name": f"Priority Fandom {suffix}",
            "slug": f"priority-fandom-{suffix}",
            "description": "Membership perks & channel priority test",
        },
    )
    assert res_fandom.status_code == 201
    fandom_payload = res_fandom.json()
    fandom_id = fandom_payload.get("fandom_id") or fandom_payload["id"]

    res_bank = await async_client.put(
        f"/api/v1/fandoms/{fandom_id}/bank-account",
        headers=owner_headers,
        json={
            "bank_code": "MBBank",
            "account_number": "0999888777",
            "account_name": "CHU FANDOM",
            "is_active": True,
        },
    )
    assert res_bank.status_code == 200

    # All fans join fandom
    for h in (tier1_headers, tier2_headers, free_headers):
        res_join = await async_client.post(
            f"/api/v1/fandoms/{fandom_id}/join", headers=h
        )
        assert res_join.status_code in (200, 201)

    # 2. Owner creates Tier 1 (perks: EXCLUSIVE_EMOJIS + PRIORITY_CHANNEL_ACCESS, NO STICKERS)
    #    and Tier 2 (all perks)
    perks_tier1 = (
        MembershipPerkBit.EXCLUSIVE_EMOJIS | MembershipPerkBit.PRIORITY_CHANNEL_ACCESS
    )
    res_t1 = await async_client.post(
        f"/api/v1/fandoms/{fandom_id}/memberships",
        headers=owner_headers,
        json={
            "name": "Silver Fan",
            "tier_level": 1,
            "price_fiat_vnd": 20000,
            "duration_days": 30,
            "permissions_bitmask": 0,
            "membership_perks_bitmask": perks_tier1,
        },
    )
    assert res_t1.status_code == 201
    tier1 = res_t1.json()
    assert tier1["membership_perks_bitmask"] == perks_tier1

    res_t2 = await async_client.post(
        f"/api/v1/fandoms/{fandom_id}/memberships",
        headers=owner_headers,
        json={
            "name": "Gold Fan",
            "tier_level": 2,
            "price_fiat_vnd": 50000,
            "duration_days": 30,
            "permissions_bitmask": 0,
            "membership_perks_bitmask": MembershipPerkBit.DEFAULT_TIER_PERKS,
        },
    )
    assert res_t2.status_code == 201
    tier2 = res_t2.json()
    assert tier2["membership_perks_bitmask"] == MembershipPerkBit.DEFAULT_TIER_PERKS

    # Provision memberships via SePay simulation
    async def buy_tier(headers: dict[str, str], role_id: str, amount: int) -> None:
        res_order = await async_client.post(
            f"/api/v1/fandoms/{fandom_id}/orders",
            headers=headers,
            json={"role_id": role_id},
        )
        assert res_order.status_code == 201
        order_code = res_order.json()["order_code"]
        res_sim = await async_client.post(
            "/api/v1/billing/sepay-simulate",
            headers=owner_headers,
            json={"order_code": order_code, "transfer_amount": amount},
        )
        assert res_sim.status_code == 200
        assert res_sim.json()["reconciliation_status"] == "MATCHED"

    await buy_tier(tier1_headers, tier1["id"], 20000)
    await buy_tier(tier2_headers, tier2["id"], 50000)

    # 3. Create Tier-2-only Channel & Public Slowmode Channel with Membership Priority
    res_vip_chan = await async_client.post(
        f"/api/v1/fandoms/{fandom_id}/channels",
        headers=owner_headers,
        json={
            "name": "gold-vip-lounge",
            "type": "TEXT",
            "is_membership_only": True,
            "min_membership_tier_level": 2,
            "membership_bypass_slowmode": True,
            "slow_mode_seconds": 30,
        },
    )
    assert res_vip_chan.status_code == 201
    vip_chan = res_vip_chan.json()
    assert vip_chan["min_membership_tier_level"] == 2
    assert vip_chan["membership_bypass_slowmode"] is True

    res_pub_chan = await async_client.post(
        f"/api/v1/fandoms/{fandom_id}/channels",
        headers=owner_headers,
        json={
            "name": "fast-vip-chat",
            "type": "TEXT",
            "is_membership_only": False,
            "min_membership_tier_level": 0,
            "membership_bypass_slowmode": True,
            "slow_mode_seconds": 30,
        },
    )
    assert res_pub_chan.status_code == 201
    pub_chan = res_pub_chan.json()
    assert pub_chan["membership_bypass_slowmode"] is True

    # Tier 1 fan CANNOT post in Tier-2-only channel -> 403
    res_t1_vip = await async_client.post(
        f"/api/v1/channels/{vip_chan['id']}/messages",
        headers=tier1_headers,
        json={"content": "Tier 1 trying Gold Lounge"},
    )
    assert res_t1_vip.status_code == 403

    # Tier 2 fan CAN post in Tier-2-only channel -> 201
    res_t2_vip = await async_client.post(
        f"/api/v1/channels/{vip_chan['id']}/messages",
        headers=tier2_headers,
        json={"content": "Tier 2 inside Gold Lounge"},
    )
    assert res_t2_vip.status_code == 201

    # 4. In public slowmode channel with membership_bypass_slowmode=True:
    # Free member hits 429 on rapid 2nd message; Tier 1 member (has PRIORITY_CHANNEL_ACCESS) bypasses!
    res_free_1 = await async_client.post(
        f"/api/v1/channels/{pub_chan['id']}/messages",
        headers=free_headers,
        json={"content": "Free msg 1"},
    )
    assert res_free_1.status_code == 201
    res_free_2 = await async_client.post(
        f"/api/v1/channels/{pub_chan['id']}/messages",
        headers=free_headers,
        json={"content": "Free msg 2 too fast"},
    )
    assert res_free_2.status_code == 429

    res_t1_1 = await async_client.post(
        f"/api/v1/channels/{pub_chan['id']}/messages",
        headers=tier1_headers,
        json={"content": "VIP msg 1"},
    )
    assert res_t1_1.status_code == 201
    res_t1_2 = await async_client.post(
        f"/api/v1/channels/{pub_chan['id']}/messages",
        headers=tier1_headers,
        json={"content": "VIP msg 2 rapid bypass"},
    )
    assert res_t1_2.status_code == 201

    # 5. Update Tier 1 to remove PRIORITY_CHANNEL_ACCESS perk -> bypass no longer applies
    res_upd_t1 = await async_client.put(
        f"/api/v1/fandoms/{fandom_id}/memberships/{tier1['id']}",
        headers=owner_headers,
        json={"membership_perks_bitmask": MembershipPerkBit.EXCLUSIVE_EMOJIS},
    )
    assert res_upd_t1.status_code == 200
    assert (
        res_upd_t1.json()["membership_perks_bitmask"]
        == MembershipPerkBit.EXCLUSIVE_EMOJIS
    )

    # Clear slowmode cooldown isn't needed for test, posting again triggers new check
    # Next message sets slowmode key since bypass is off, following rapid message gets 429
    await async_client.post(
        f"/api/v1/channels/{pub_chan['id']}/messages",
        headers=tier1_headers,
        json={"content": "VIP without priority 1"},
    )
    res_t1_slow = await async_client.post(
        f"/api/v1/channels/{pub_chan['id']}/messages",
        headers=tier1_headers,
        json={"content": "VIP without priority 2"},
    )
    assert res_t1_slow.status_code == 429
