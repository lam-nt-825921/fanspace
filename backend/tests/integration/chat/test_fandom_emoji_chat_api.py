"""Integration tests for Fandom exclusive Emoji & Sticker listing and chat enforcement."""

import uuid
import pytest
from httpx import ASGITransport, AsyncClient

from app.core.database import AsyncSessionLocal
from app.core.security import create_access_token
from app.main import app
from app.modules.fandom.models import FandomEmoji
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
async def test_fandom_emoji_and_sticker_chat_unlock_and_enforcement():
    """Verifies GET /fandoms/{slug}/emojis unlock flags and 403 enforcement in chat messages & reactions."""
    owner, owner_headers = await _create_test_user("emj_owner", "Chủ Fandom")
    fan_free, free_headers = await _create_test_user("emj_free", "Fan Thường")
    fan_tier1, tier1_headers = await _create_test_user("emj_t1", "Fan Bạc")

    slug = f"fandom-emoji-{uuid.uuid4().hex[:8]}"

    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as client:
        # 1. Owner creates fandom
        res_fandom = await client.post(
            "/api/v1/fandoms",
            headers=owner_headers,
            json={
                "name": f"Fandom Emoji {slug}",
                "slug": slug,
                "category": "Music",
                "is_public": True,
                "admission_mode": "OPEN",
            },
        )
        assert res_fandom.status_code == 201
        fandom_id = uuid.UUID(res_fandom.json()["fandom_id"])

        # 2. Both fans join the fandom
        for hdr in (free_headers, tier1_headers):
            join_res = await client.post(f"/api/v1/fandoms/{slug}/join", headers=hdr)
            assert join_res.status_code in (200, 201)

        # 3. Owner sets up bank account and 2 Membership Tiers (Tier 1 & Tier 2)
        await client.put(
            f"/api/v1/fandoms/{slug}/bank-account",
            headers=owner_headers,
            json={
                "bank_code": "MBBank",
                "account_number": "0389112233",
                "account_name": "CHU FANDOM",
                "is_active": True,
            },
        )
        t1_res = await client.post(
            f"/api/v1/fandoms/{slug}/memberships",
            headers=owner_headers,
            json={
                "name": "Hội viên Bạc",
                "tier_level": 1,
                "color_hex": "#42A5F5",
                "price_fiat_vnd": 30_000,
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
                "price_fiat_vnd": 90_000,
                "duration_days": 30,
            },
        )
        assert t2_res.status_code == 201

        # 4. fan_tier1 buys Tier 1 membership
        order_res = await client.post(
            f"/api/v1/fandoms/{slug}/orders",
            headers=tier1_headers,
            json={"role_id": tier1_id},
        )
        order_code = order_res.json()["order_code"]
        await client.post(
            "/api/v1/billing/sepay-simulate",
            headers=owner_headers,
            json={"order_code": order_code},
        )

        # 5. Insert 1 Tier-1 EMOJI and 1 Tier-2 STICKER for this Fandom
        async with AsyncSessionLocal() as db:
            e1 = FandomEmoji(
                fandom_id=fandom_id,
                code="silver_heart",
                name="Tim Bạc",
                asset_type="EMOJI",
                image_url="https://res.cloudinary.com/demo/image/upload/silver_heart.png",
                min_tier_level=1,
                created_by=owner.id,
            )
            e2 = FandomEmoji(
                fandom_id=fandom_id,
                code="gold_dragon",
                name="Rồng Vàng",
                asset_type="STICKER",
                image_url="https://res.cloudinary.com/demo/image/upload/gold_dragon.png",
                min_tier_level=2,
                created_by=owner.id,
            )
            db.add_all([e1, e2])
            await db.commit()

        # 6. Check GET /fandoms/{slug}/emojis for fan_free, fan_tier1, and owner
        free_list = await client.get(
            f"/api/v1/fandoms/{slug}/emojis", headers=free_headers
        )
        assert free_list.status_code == 200
        free_items = {i["code"]: i for i in free_list.json()["items"]}
        assert free_items["silver_heart"]["is_unlocked"] is False
        assert free_items["gold_dragon"]["is_unlocked"] is False

        t1_list = await client.get(
            f"/api/v1/fandoms/{slug}/emojis", headers=tier1_headers
        )
        assert t1_list.status_code == 200
        t1_items = {i["code"]: i for i in t1_list.json()["items"]}
        assert t1_items["silver_heart"]["is_unlocked"] is True
        assert t1_items["gold_dragon"]["is_unlocked"] is False

        owner_list = await client.get(
            f"/api/v1/fandoms/{slug}/emojis", headers=owner_headers
        )
        assert owner_list.status_code == 200
        owner_items = {i["code"]: i for i in owner_list.json()["items"]}
        assert owner_items["silver_heart"]["is_unlocked"] is True
        assert owner_items["gold_dragon"]["is_unlocked"] is True

        # 7. Get general text channel
        ch_res = await client.get(
            f"/api/v1/fandoms/{slug}/channels", headers=owner_headers
        )
        text_ch = next(
            c
            for c in ch_res.json()["channels"]
            if c["type"] == "TEXT" and not c["is_announcement"]
        )
        channel_id = text_ch["id"]

        # 8. fan_free attempts to send :silver_heart: -> 403 Forbidden
        bad_msg = await client.post(
            f"/api/v1/channels/{channel_id}/messages",
            headers=free_headers,
            json={"content": "Chào cả nhà :silver_heart:!"},
        )
        assert bad_msg.status_code == 403

        # 9. fan_tier1 sends :silver_heart: -> 201 Created
        ok_msg = await client.post(
            f"/api/v1/channels/{channel_id}/messages",
            headers=tier1_headers,
            json={"content": "Chào cả nhà :silver_heart:!"},
        )
        assert ok_msg.status_code == 201
        msg_id = ok_msg.json()["id"]

        # 10. fan_tier1 attempts to send Tier-2 Sticker :gold_dragon: -> 403 Forbidden
        bad_sticker = await client.post(
            f"/api/v1/channels/{channel_id}/messages",
            headers=tier1_headers,
            json={
                "content": ":gold_dragon:",
                "attachments": [
                    {
                        "url": "https://res.cloudinary.com/demo/image/upload/gold_dragon.png",
                        "type": "STICKER",
                        "filename": ":gold_dragon:",
                    }
                ],
            },
        )
        assert bad_sticker.status_code == 403

        # 11. Reactions: fan_free cannot react with :silver_heart:, fan_tier1 can!
        bad_react = await client.post(
            f"/api/v1/channels/{channel_id}/messages/{msg_id}/reactions",
            headers=free_headers,
            json={"emoji": ":silver_heart:"},
        )
        assert bad_react.status_code == 403

        ok_react = await client.post(
            f"/api/v1/channels/{channel_id}/messages/{msg_id}/reactions",
            headers=tier1_headers,
            json={"emoji": ":silver_heart:"},
        )
        assert ok_react.status_code == 200
        assert ":silver_heart:" in ok_react.json()["reactions"]
