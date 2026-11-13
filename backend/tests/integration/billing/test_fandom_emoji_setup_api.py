"""Integration and unit tests for Fandom Owner Emoji & Sticker Setup APIs (Phase 3)."""

import uuid
import pytest
from httpx import ASGITransport, AsyncClient

from app.core.database import AsyncSessionLocal
from app.core.security import create_access_token, get_password_hash
from app.main import app
from app.modules.identity.models import User
from app.modules.media.schemas import MediaResourceType, MediaTarget
from app.modules.media.service import MediaService


@pytest.fixture
async def async_client():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        yield client


def test_media_target_fandom_emoji_validation():
    """Verifies MediaTarget.FANDOM_EMOJI accepts valid PNG bytes and builds a fandom emoji public_id."""
    fandom_id = uuid.uuid4()
    user_id = uuid.uuid4()
    public_id, overwrite = MediaService.build_public_id(
        user_id=user_id,
        target=MediaTarget.FANDOM_EMOJI,
        entity_id=fandom_id,
    )
    assert public_id.startswith(f"fanspace/fandoms/{fandom_id}/emojis/")
    assert overwrite is False

    # Valid PNG magic bytes
    png_bytes = b"\x89PNG\r\n\x1a\n" + b"\x00" * 32
    r_type, ext = MediaService.validate_file_bytes(png_bytes, MediaTarget.FANDOM_EMOJI)
    assert r_type == MediaResourceType.IMAGE
    assert ext == "png"


@pytest.mark.asyncio
async def test_fandom_emoji_and_sticker_crud_lifecycle(async_client: AsyncClient):
    """Verifies Owner CRUD for Fandom Emojis and Stickers, duplicate code checks, and non-owner 403."""
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

    owner_headers = await create_user_headers("owner_emj")
    fan_headers = await create_user_headers("fan_emj")

    res_fandom = await async_client.post(
        "/api/v1/fandoms",
        headers=owner_headers,
        json={
            "name": f"Emoji Setup Fandom {suffix}",
            "slug": f"emoji-setup-{suffix}",
            "description": "Testing emoji setup",
        },
    )
    assert res_fandom.status_code == 201
    fandom_payload = res_fandom.json()
    fandom_id = fandom_payload.get("fandom_id") or fandom_payload["id"]

    # 1. Owner creates an EMOJI unlocked at Tier 1
    res_create_emoji = await async_client.post(
        f"/api/v1/fandoms/{fandom_id}/emojis",
        headers=owner_headers,
        json={
            "code": ":heart_fire:",
            "name": "Trái tim rực lửa",
            "asset_type": "EMOJI",
            "image_url": "https://res.cloudinary.com/demo/image/upload/fanspace/fandoms/heart_fire.png",
            "min_tier_level": 1,
        },
    )
    assert res_create_emoji.status_code == 201
    emoji_data = res_create_emoji.json()
    assert emoji_data["code"] == "heart_fire"
    assert emoji_data["shortcode"] == ":heart_fire:"
    assert emoji_data["asset_type"] == "EMOJI"
    assert emoji_data["min_tier_level"] == 1
    emoji_id = emoji_data["id"]

    # 2. Owner creates a STICKER unlocked at Tier 3
    res_create_sticker = await async_client.post(
        f"/api/v1/fandoms/{fandom_id}/emojis",
        headers=owner_headers,
        json={
            "code": "super_cheer",
            "name": "Cổ vũ siêu cấp",
            "asset_type": "STICKER",
            "image_url": "https://res.cloudinary.com/demo/image/upload/fanspace/fandoms/super_cheer.webp",
            "min_tier_level": 3,
        },
    )
    assert res_create_sticker.status_code == 201
    sticker_data = res_create_sticker.json()
    assert sticker_data["code"] == "super_cheer"
    assert sticker_data["asset_type"] == "STICKER"
    assert sticker_data["min_tier_level"] == 3

    # 3. Duplicate shortcode in same fandom -> 409 Conflict
    res_dup = await async_client.post(
        f"/api/v1/fandoms/{fandom_id}/emojis",
        headers=owner_headers,
        json={
            "code": "heart_fire",
            "name": "Trùng mã",
            "asset_type": "EMOJI",
            "image_url": "https://res.cloudinary.com/demo/image/upload/fanspace/fandoms/dup.png",
            "min_tier_level": 2,
        },
    )
    assert res_dup.status_code == 409

    # 4. Non-owner cannot create, update, or delete -> 403 Forbidden
    res_fan_create = await async_client.post(
        f"/api/v1/fandoms/{fandom_id}/emojis",
        headers=fan_headers,
        json={
            "code": "fan_hack",
            "name": "Fan Hack",
            "asset_type": "EMOJI",
            "image_url": "https://res.cloudinary.com/demo/image/upload/fanspace/fandoms/hack.png",
            "min_tier_level": 1,
        },
    )
    assert res_fan_create.status_code == 403

    res_fan_del = await async_client.delete(
        f"/api/v1/fandoms/{fandom_id}/emojis/{emoji_id}",
        headers=fan_headers,
    )
    assert res_fan_del.status_code == 403

    # 5. Owner updates min_tier_level and name of the emoji
    res_update = await async_client.put(
        f"/api/v1/fandoms/{fandom_id}/emojis/{emoji_id}",
        headers=owner_headers,
        json={
            "name": "Trái tim kim cương",
            "min_tier_level": 4,
        },
    )
    assert res_update.status_code == 200
    updated_data = res_update.json()
    assert updated_data["name"] == "Trái tim kim cương"
    assert updated_data["min_tier_level"] == 4

    # 6. Owner deletes the emoji
    res_del = await async_client.delete(
        f"/api/v1/fandoms/{fandom_id}/emojis/{emoji_id}",
        headers=owner_headers,
    )
    assert res_del.status_code == 200

    # Verify list now only has the sticker
    res_list = await async_client.get(
        f"/api/v1/fandoms/{fandom_id}/emojis",
        headers=owner_headers,
    )
    assert res_list.status_code == 200
    items = res_list.json()["items"]
    assert len(items) == 1
    assert items[0]["code"] == "super_cheer"
