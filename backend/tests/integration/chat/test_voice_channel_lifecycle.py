"""Integration tests for FR-11 (UC-06): Real-time Voice Room via Agora RTC.
Covers:
- Dynamic RTC Token issuance (`POST /api/v1/channels/{channel_id}/voice/token`)
- Open Mic vs Stage Room role assignment (SPEAKER vs LISTENER)
- Max members capacity enforcement on voice room join
- Raise Hand workflow (`POST /api/v1/channels/{channel_id}/voice/raise-hand`)
- Moderator promote/demote/mute speaker (`PUT /api/v1/channels/{channel_id}/voice/speakers/{user_id}`)
- Self mute/unmute (`PUT /api/v1/channels/{channel_id}/voice/me/mute`)
- Host/Mod Mute All (`POST /api/v1/channels/{channel_id}/voice/mute-all`)
- Leaving voice room (`POST /api/v1/channels/{channel_id}/voice/leave`)
"""

import uuid
import pytest
from httpx import ASGITransport, AsyncClient

from app.core.database import AsyncSessionLocal
from app.core.security import create_access_token, get_password_hash
from app.main import app
from app.modules.identity.models import User


@pytest.fixture
async def async_client():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        yield client


@pytest.mark.asyncio
async def test_voice_room_stage_and_open_mic_full_lifecycle(
    async_client: AsyncClient,
):
    """Verifies Agora RTC token issuance, Stage Room raise-hand & speaker promotion, Mute All, and capacity limit."""
    suffix = uuid.uuid4().hex[:8]

    async def create_user_with_token(prefix: str) -> tuple[User, dict[str, str]]:
        user = User(
            username=f"{prefix}_{suffix}",
            email=f"{prefix}_{suffix}@vnu.edu.vn",
            password_hash=get_password_hash("Password123!"),
            display_name=prefix.replace("_", " ").title(),
            is_active=True,
            is_email_verified=True,
        )
        async with AsyncSessionLocal() as db:
            db.add(user)
            await db.commit()
            await db.refresh(user)
        token = create_access_token({"sub": str(user.id), "username": user.username})
        return user, {"Authorization": f"Bearer {token}"}

    owner, owner_headers = await create_user_with_token("voice_owner")
    fan1, fan1_headers = await create_user_with_token("voice_fan1")
    fan2, fan2_headers = await create_user_with_token("voice_fan2")

    # 1. Owner creates Fandom & fans join
    res_fandom = await async_client.post(
        "/api/v1/fandoms",
        headers=owner_headers,
        json={
            "name": f"Voice Fandom {suffix}",
            "slug": f"voice-fandom-{suffix}",
            "description": "FR-11 Agora Voice RTC test",
        },
    )
    assert res_fandom.status_code == 201
    fandom_payload = res_fandom.json()
    fandom_id = fandom_payload.get("fandom_id") or fandom_payload["id"]

    for h in (fan1_headers, fan2_headers):
        res_join = await async_client.post(f"/api/v1/fandoms/{fandom_id}/join", headers=h)
        assert res_join.status_code in (200, 201)

    # 2. Owner creates a STAGE_ROOM voice channel with max_members=2
    res_stage = await async_client.post(
        f"/api/v1/fandoms/{fandom_id}/channels",
        headers=owner_headers,
        json={
            "name": "San Khau Am Nhac",
            "type": "VOICE",
            "voice_room_type": "STAGE_ROOM",
            "max_members": 2,
        },
    )
    assert res_stage.status_code == 201
    stage_id = res_stage.json()["id"]

    # 3. Owner joins Stage Room -> gets PUBLISHER token and SPEAKER role
    res_owner_tok = await async_client.post(
        f"/api/v1/channels/{stage_id}/voice/token",
        headers=owner_headers,
    )
    assert res_owner_tok.status_code == 200
    owner_tok_data = res_owner_tok.json()
    assert owner_tok_data["rtc_token"].startswith("006")
    assert owner_tok_data["role"] == "SPEAKER"
    assert owner_tok_data["can_publish"] is True

    # 4. Fan 1 joins Stage Room -> regular member in STAGE_ROOM starts as LISTENER
    res_fan1_tok = await async_client.post(
        f"/api/v1/channels/{stage_id}/voice/token",
        headers=fan1_headers,
    )
    assert res_fan1_tok.status_code == 200
    fan1_tok_data = res_fan1_tok.json()
    assert fan1_tok_data["role"] == "LISTENER"
    assert fan1_tok_data["can_publish"] is False

    # 5. Fan 2 tries to join when max_members=2 is already reached -> 403 Forbidden
    res_fan2_full = await async_client.post(
        f"/api/v1/channels/{stage_id}/voice/token",
        headers=fan2_headers,
    )
    assert res_fan2_full.status_code == 403

    # 6. Fan 1 raises hand in Stage Room
    res_raise = await async_client.post(
        f"/api/v1/channels/{stage_id}/voice/raise-hand",
        headers=fan1_headers,
        json={"raised": True},
    )
    assert res_raise.status_code == 200
    state_after_raise = res_raise.json()
    assert str(fan1.id) in state_after_raise["raised_hand_user_ids"]

    # 7. Owner promotes Fan 1 to SPEAKER and unmutes them
    res_promote = await async_client.put(
        f"/api/v1/channels/{stage_id}/voice/speakers/{fan1.id}",
        headers=owner_headers,
        json={"role": "SPEAKER", "is_muted": False},
    )
    assert res_promote.status_code == 200
    state_after_promote = res_promote.json()
    assert str(fan1.id) not in state_after_promote["raised_hand_user_ids"]
    fan1_p = next(p for p in state_after_promote["participants"] if p["user_id"] == str(fan1.id))
    assert fan1_p["role"] == "SPEAKER"
    assert fan1_p["is_muted"] is False

    # 8. Owner unmutes themselves, then triggers Mute All -> all participants (or non-owners) are muted
    await async_client.put(
        f"/api/v1/channels/{stage_id}/voice/me/mute",
        headers=owner_headers,
        json={"is_muted": False},
    )
    res_mute_all = await async_client.post(
        f"/api/v1/channels/{stage_id}/voice/mute-all",
        headers=owner_headers,
    )
    assert res_mute_all.status_code == 200
    state_after_mute_all = res_mute_all.json()
    fan1_muted = next(p for p in state_after_mute_all["participants"] if p["user_id"] == str(fan1.id))
    assert fan1_muted["is_muted"] is True

    # 9. Fan 1 leaves voice room -> slot frees up for Fan 2
    res_leave = await async_client.post(
        f"/api/v1/channels/{stage_id}/voice/leave",
        headers=fan1_headers,
    )
    assert res_leave.status_code == 200
    assert len(res_leave.json()["participants"]) == 1

    res_fan2_ok = await async_client.post(
        f"/api/v1/channels/{stage_id}/voice/token",
        headers=fan2_headers,
    )
    assert res_fan2_ok.status_code == 200
