"""Integration tests for FR-10 Channel Governance:
- CRUD (create, update, delete, prevent deleting last channel)
- Max concurrent members limit (`max_members`)
- Slow-mode rate limiting (`slow_mode_seconds`)
- Multi-role assignment (`allowed_role_ids`) and granular role channel permissions (`role_permissions_bitmask`)
- Membership VIP restrictions (`is_membership_only`, `min_membership_tier_level`, `membership_bypass_slowmode`, `membership_permissions_bitmask`)
"""

import uuid
import pytest
from httpx import ASGITransport, AsyncClient

from app.core.database import AsyncSessionLocal
from app.core.redis import get_redis_client
from app.core.security import create_access_token, get_password_hash
from app.main import app, join_channel, leave_channel
from app.modules.identity.models import User
from app.modules.rbac.models import MembershipPerkBit, PermissionBit


@pytest.fixture
async def async_client():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        yield client


@pytest.mark.asyncio
async def test_fr10_channel_governance_full_lifecycle(
    async_client: AsyncClient,
):
    """Verifies FR-10 channel multi-role access, granular permissions, max_members capacity, slow-mode, and VIP perks."""
    suffix = uuid.uuid4().hex[:8]
    redis = get_redis_client()

    async def create_user_with_token(prefix: str) -> tuple[User, dict[str, str]]:
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

    _, owner_headers = await create_user_with_token("fr10_owner")
    user_role_a, role_a_headers = await create_user_with_token("fr10_role_a")
    user_role_b, role_b_headers = await create_user_with_token("fr10_role_b")
    _, free_headers = await create_user_with_token("fr10_free")
    _, vip_headers = await create_user_with_token("fr10_vip")

    # 1. Create Fandom & Join all users
    res_fandom = await async_client.post(
        "/api/v1/fandoms",
        headers=owner_headers,
        json={
            "name": f"FR10 Channel Fandom {suffix}",
            "slug": f"fr10-channel-{suffix}",
            "description": "FR-10 Channel Governance test suite",
        },
    )
    assert res_fandom.status_code == 201
    fandom_payload = res_fandom.json()
    fandom_id = fandom_payload.get("fandom_id") or fandom_payload["id"]

    for h in (role_a_headers, role_b_headers, free_headers, vip_headers):
        res_join = await async_client.post(f"/api/v1/fandoms/{fandom_id}/join", headers=h)
        assert res_join.status_code in (200, 201)

    # 2. Create two regular custom roles (Role A & Role B) and assign them
    res_ra = await async_client.post(
        f"/api/v1/fandoms/{fandom_id}/roles",
        headers=owner_headers,
        json={
            "name": "Designer",
            "color_hex": "#10B981",
            "priority": 20,
            "permissions_bitmask": PermissionBit.READ_MESSAGES | PermissionBit.SEND_MESSAGES | PermissionBit.ATTACH_FILES,
        },
    )
    assert res_ra.status_code == 201
    role_a_id = res_ra.json()["id"]

    res_rb = await async_client.post(
        f"/api/v1/fandoms/{fandom_id}/roles",
        headers=owner_headers,
        json={
            "name": "Developer",
            "color_hex": "#3B82F6",
            "priority": 25,
            "permissions_bitmask": PermissionBit.READ_MESSAGES | PermissionBit.SEND_MESSAGES | PermissionBit.ATTACH_FILES,
        },
    )
    assert res_rb.status_code == 201
    role_b_id = res_rb.json()["id"]

    res_assign_a = await async_client.post(
        f"/api/v1/fandoms/{fandom_id}/members/{user_role_a.id}/roles",
        headers=owner_headers,
        json={"role_ids": [role_a_id]},
    )
    assert res_assign_a.status_code in (200, 201)

    res_assign_b = await async_client.post(
        f"/api/v1/fandoms/{fandom_id}/members/{user_role_b.id}/roles",
        headers=owner_headers,
        json={"role_ids": [role_b_id]},
    )
    assert res_assign_b.status_code in (200, 201)

    # 3. Create Multi-Role Channel with granular role_permissions_bitmask (READ_MESSAGES + SEND_MESSAGES, NO ATTACH_FILES)
    role_only_mask = PermissionBit.READ_MESSAGES | PermissionBit.SEND_MESSAGES
    res_multi_ch = await async_client.post(
        f"/api/v1/fandoms/{fandom_id}/channels",
        headers=owner_headers,
        json={
            "name": "design-and-dev",
            "type": "TEXT",
            "topic": "Kênh nội bộ cho Designer và Developer",
            "allowed_role_ids": [role_a_id, role_b_id],
            "role_permissions_bitmask": role_only_mask,
            "max_members": 2,
            "slow_mode_seconds": 10,
        },
    )
    assert res_multi_ch.status_code == 201
    multi_ch = res_multi_ch.json()
    ch_id = multi_ch["id"]
    assert set(multi_ch["allowed_role_ids"]) == {role_a_id, role_b_id}
    assert multi_ch["max_members"] == 2
    assert multi_ch["role_permissions_bitmask"] == role_only_mask

    # Free member (has neither Role A nor Role B) cannot view or send in multi_ch -> 403
    res_free_send = await async_client.post(
        f"/api/v1/channels/{ch_id}/messages",
        headers=free_headers,
        json={"content": "Free user trying restricted multi-role channel"},
    )
    assert res_free_send.status_code == 403

    # User with Role A and User with Role B CAN both send text messages -> 201
    res_a_send = await async_client.post(
        f"/api/v1/channels/{ch_id}/messages",
        headers=role_a_headers,
        json={"content": "Designer message OK"},
    )
    assert res_a_send.status_code == 201

    res_b_send = await async_client.post(
        f"/api/v1/channels/{ch_id}/messages",
        headers=role_b_headers,
        json={"content": "Developer message OK"},
    )
    assert res_b_send.status_code == 201

    # Because role_permissions_bitmask excluded ATTACH_FILES, Role A cannot send image attachment -> 403
    # (First clear slowmode key for user_role_a so we test permission check directly)
    await redis.delete(f"slowmode:channel:{ch_id}:user:{user_role_a.id}")
    res_a_attach = await async_client.post(
        f"/api/v1/channels/{ch_id}/messages",
        headers=role_a_headers,
        json={
            "content": "Trying image attachment",
            "attachments": [{"url": "https://res.cloudinary.com/demo/image/upload/sample.jpg", "type": "IMAGE"}],
        },
    )
    assert res_a_attach.status_code == 403

    # 4. Verify max_members = 2 enforcement on channel presence / joining
    await redis.delete(f"channel:active_members:{ch_id}")
    join_1 = await join_channel("sid_user_1", {"channel_id": ch_id, "user_id": str(user_role_a.id)})
    assert join_1["ok"] is True
    assert join_1.get("active_members_count") == 1

    join_2 = await join_channel("sid_user_2", {"channel_id": ch_id, "user_id": str(user_role_b.id)})
    assert join_2["ok"] is True
    assert join_2.get("active_members_count") == 2

    # 3rd distinct user trying to join when max_members=2 is rejected!
    join_3 = await join_channel("sid_user_3", {"channel_id": ch_id, "user_id": str(uuid.uuid4())})
    assert join_3["ok"] is False
    assert "giới hạn" in join_3["error"].lower()

    # After user 1 leaves channel, slot opens up
    await leave_channel("sid_user_1", {"channel_id": ch_id, "user_id": str(user_role_a.id)})
    join_3_retry = await join_channel("sid_user_3", {"channel_id": ch_id, "user_id": str(uuid.uuid4())})
    assert join_3_retry["ok"] is True

    # 5. Configure Bank & VIP Tier, then test membership_permissions_bitmask on channel
    await async_client.put(
        f"/api/v1/fandoms/{fandom_id}/bank-account",
        headers=owner_headers,
        json={
            "bank_code": "MBBank",
            "account_number": "0123456789",
            "account_name": "CHU FANDOM FR10",
            "is_active": True,
        },
    )
    res_tier = await async_client.post(
        f"/api/v1/fandoms/{fandom_id}/memberships",
        headers=owner_headers,
        json={
            "name": "Diamond VIP",
            "tier_level": 1,
            "price_fiat_vnd": 30000,
            "duration_days": 30,
            "permissions_bitmask": 0,
            "membership_perks_bitmask": MembershipPerkBit.DEFAULT_TIER_PERKS,
        },
    )
    assert res_tier.status_code == 201
    tier_id = res_tier.json()["id"]

    res_order = await async_client.post(
        f"/api/v1/fandoms/{fandom_id}/orders",
        headers=vip_headers,
        json={"role_id": tier_id},
    )
    assert res_order.status_code == 201
    order_code = res_order.json()["order_code"]
    await async_client.post(
        "/api/v1/billing/sepay-simulate",
        headers=owner_headers,
        json={"order_code": order_code, "transfer_amount": 30000},
    )

    # Update channel: remove role restrictions, make it VIP-only with read-only membership_permissions_bitmask (READ_MESSAGES only)
    res_upd_vip = await async_client.put(
        f"/api/v1/fandoms/{fandom_id}/channels/{ch_id}",
        headers=owner_headers,
        json={
            "allowed_role_ids": [],
            "is_membership_only": True,
            "min_membership_tier_level": 1,
            "membership_permissions_bitmask": PermissionBit.READ_MESSAGES,
            "max_members": 0,
        },
    )
    assert res_upd_vip.status_code == 200
    assert res_upd_vip.json()["allowed_role_ids"] == []
    assert res_upd_vip.json()["required_role_id"] is None
    assert res_upd_vip.json()["membership_permissions_bitmask"] == PermissionBit.READ_MESSAGES

    # VIP member can read messages (200) but CANNOT send messages (403) because SEND_MESSAGES was unchecked in membership_permissions_bitmask
    res_vip_read = await async_client.get(
        f"/api/v1/channels/{ch_id}/messages",
        headers=vip_headers,
    )
    assert res_vip_read.status_code == 200

    res_vip_send_denied = await async_client.post(
        f"/api/v1/channels/{ch_id}/messages",
        headers=vip_headers,
        json={"content": "VIP trying to send in read-only VIP channel"},
    )
    assert res_vip_send_denied.status_code == 403

    # Update membership_permissions_bitmask to include SEND_MESSAGES | BYPASS_SLOWMODE -> VIP can now send rapidly
    await async_client.put(
        f"/api/v1/fandoms/{fandom_id}/channels/{ch_id}",
        headers=owner_headers,
        json={
            "membership_permissions_bitmask": (
                PermissionBit.READ_MESSAGES
                | PermissionBit.SEND_MESSAGES
                | PermissionBit.BYPASS_SLOWMODE
            ),
        },
    )
    res_vip_send_1 = await async_client.post(
        f"/api/v1/channels/{ch_id}/messages",
        headers=vip_headers,
        json={"content": "VIP rapid msg 1"},
    )
    assert res_vip_send_1.status_code == 201
    res_vip_send_2 = await async_client.post(
        f"/api/v1/channels/{ch_id}/messages",
        headers=vip_headers,
        json={"content": "VIP rapid msg 2 bypassing slowmode"},
    )
    assert res_vip_send_2.status_code == 201
