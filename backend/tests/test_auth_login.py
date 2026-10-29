"""Integration tests for email/password authentication and session management.

Covers:
- Valid login requests (minimal fields and optional mobile device metadata).
- Missing required fields (`email`, `password`, empty payload, and mobile `device_id`).
- Invalid email formats, unknown accounts, wrong passwords, and 5-attempt brute-force lockout.
- Single active session per platform enforcement, refresh token rotation, and account deletion.
"""

import uuid
import pytest
from httpx import ASGITransport, AsyncClient
from app.main import app
from app.core.redis import redis_client


async def _register_verified_user(
    client: AsyncClient,
    *,
    email: str,
    username: str,
    password: str,
    display_name: str = "Verified Tester",
    platform: str | None = None,
    device_id: str | None = None,
    headers: dict | None = None,
) -> dict:
    """Completes staged registration and OTP verification to provision an active test user."""
    payload = {
        "email": email,
        "username": username,
        "password": password,
        "display_name": display_name,
    }
    if platform:
        payload["platform"] = platform
    if device_id:
        payload["device_id"] = device_id

    reg_res = await client.post("/api/v1/auth/register", json=payload, headers=headers)
    assert reg_res.status_code == 202
    otp_code = reg_res.json()["dev_otp"]

    verify_res = await client.post(
        "/api/v1/auth/email/verify-otp",
        json={"email": email, "code": otp_code, "purpose": "VERIFY_EMAIL"},
    )
    assert verify_res.status_code == 200
    return verify_res.json()


# ==============================================================================
# 1. VALID AUTHENTICATION REQUESTS
# ==============================================================================


@pytest.mark.asyncio
async def test_login_valid_minimal_and_full_fields():
    """Authenticates a verified user with minimal credentials and with mobile platform metadata."""
    transport = ASGITransport(app=app)
    uid = uuid.uuid4().hex[:8]
    email = f"login_ok_{uid}@example.com"
    username = f"login_ok_{uid}"
    password = "CorrectPassword123!"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        await _register_verified_user(
            client,
            email=email,
            username=username,
            password=password,
            display_name="Login Valid User",
        )

        # Minimal required fields (email, password)
        login_min = await client.post(
            "/api/v1/auth/login",
            json={"email": email, "password": password},
        )
        assert login_min.status_code == 200
        data_min = login_min.json()
        assert data_min["success"] is True
        assert data_min["tokens"]["access_token"]
        assert data_min["tokens"]["refresh_token"]
        assert data_min["user"]["email"] == email
        assert data_min["user"]["is_email_verified"] is True

        # Full payload with optional mobile platform and device_id
        login_full = await client.post(
            "/api/v1/auth/login",
            json={
                "email": email,
                "password": password,
                "platform": "MOBILE",
                "device_id": f"ios_device_{uid}",
            },
            headers={"User-Agent": "FanSpace iOS/1.0"},
        )
        assert login_full.status_code == 200
        assert login_full.json()["tokens"]["session_id"] is not None


# ==============================================================================
# 2. MISSING REQUIRED FIELDS
# ==============================================================================


@pytest.mark.asyncio
@pytest.mark.parametrize("missing_field", ["email", "password"])
async def test_login_missing_required_fields(missing_field: str):
    """Rejects login requests missing email or password with 422 Unprocessable Entity."""
    transport = ASGITransport(app=app)
    payload = {
        "email": "someuser@example.com",
        "password": "SomePassword123!",
    }
    payload.pop(missing_field)

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        res = await client.post("/api/v1/auth/login", json=payload)
        assert res.status_code == 422
        errors = res.json()["detail"]
        assert any(missing_field in err["loc"] for err in errors)


@pytest.mark.asyncio
async def test_login_empty_payload():
    """Rejects an empty login payload with 422 Unprocessable Entity."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        res = await client.post("/api/v1/auth/login", json={})
        assert res.status_code == 422
        assert len(res.json()["detail"]) >= 2


@pytest.mark.asyncio
async def test_login_mobile_missing_device_id():
    """Rejects mobile login requests that omit device_id with 400 Bad Request."""
    transport = ASGITransport(app=app)
    uid = uuid.uuid4().hex[:6]
    email = f"mob_login_{uid}@example.com"
    password = "Password123!"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        await _register_verified_user(
            client,
            email=email,
            username=f"mob_login_{uid}",
            password=password,
        )
        res = await client.post(
            "/api/v1/auth/login",
            json={
                "email": email,
                "password": password,
                "platform": "MOBILE",
            },
        )
        assert res.status_code == 400
        assert "mã định danh thiết bị" in res.json()["detail"]


# ==============================================================================
# 3. INVALID CREDENTIALS & BRUTE-FORCE LOCKOUT
# ==============================================================================


@pytest.mark.asyncio
@pytest.mark.parametrize("bad_email", ["not-an-email", "missing@", "@missing.com", ""])
async def test_login_invalid_email_format(bad_email: str):
    """Rejects malformed email addresses with 422 Unprocessable Entity."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        res = await client.post(
            "/api/v1/auth/login",
            json={"email": bad_email, "password": "SomePassword123!"},
        )
        assert res.status_code == 422


@pytest.mark.asyncio
async def test_login_nonexistent_email_and_wrong_password():
    """Returns 401 Unauthorized for unknown emails or incorrect passwords."""
    transport = ASGITransport(app=app)
    uid = uuid.uuid4().hex[:6]
    email = f"real_{uid}@example.com"
    password = "RealPassword123!"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        await _register_verified_user(
            client,
            email=email,
            username=f"real_{uid}",
            password=password,
        )

        # Unregistered email -> 401
        res_unknown = await client.post(
            "/api/v1/auth/login",
            json={"email": f"nonexistent_{uid}@example.com", "password": password},
        )
        assert res_unknown.status_code == 401

        # Registered email with wrong password -> 401
        res_wrong_pwd = await client.post(
            "/api/v1/auth/login",
            json={"email": email, "password": "WrongPassword999!"},
        )
        assert res_wrong_pwd.status_code == 401


@pytest.mark.asyncio
async def test_login_lockout_rate_limit():
    """Locks the account for 15 minutes (429 Too Many Requests) after 5 consecutive failed password attempts."""
    transport = ASGITransport(app=app)
    email = f"brute_{uuid.uuid4().hex[:6]}@example.com"
    username = f"brute_{uuid.uuid4().hex[:6]}"
    password = "CorrectPassword123!"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        await _register_verified_user(
            client,
            email=email,
            username=username,
            password=password,
            platform="WEB",
        )

        for _ in range(5):
            bad = await client.post(
                "/api/v1/auth/login",
                json={"email": email, "password": "WrongPassword!"},
            )
            assert bad.status_code == 401

        # 6th attempt triggers 429 lockout
        locked = await client.post(
            "/api/v1/auth/login",
            json={"email": email, "password": "WrongPassword!"},
        )
        assert locked.status_code == 429
        assert "khóa bảo vệ" in locked.json()["detail"]

        # Valid password is also rejected while lockout is active
        locked_correct = await client.post(
            "/api/v1/auth/login",
            json={"email": email, "password": password},
        )
        assert locked_correct.status_code == 429

        await redis_client.delete(f"ratelimit:login:failed:{email}")


# ==============================================================================
# 4. MULTI-PLATFORM SESSION ENFORCEMENT, TOKEN ROTATION & ACCOUNT DELETION
# ==============================================================================


@pytest.mark.asyncio
async def test_single_active_session_per_platform():
    """Enforces one active session per platform (new MOBILE login revokes previous MOBILE session while keeping WEB active)."""
    transport = ASGITransport(app=app)
    email = f"user_{uuid.uuid4().hex[:6]}@example.com"
    username = f"u_{uuid.uuid4().hex[:6]}"
    password = "StrongPassword123!"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        res_a = await _register_verified_user(
            client,
            email=email,
            username=username,
            password=password,
            display_name="Multi Device User",
            platform="MOBILE",
            device_id="device_phone_A",
            headers={"User-Agent": "FanSpace Android App 1.0 (Pixel 7)"},
        )
        token_a = res_a["tokens"]["access_token"]

        res_web = await client.post(
            "/api/v1/auth/login",
            json={
                "email": email,
                "password": password,
                "platform": "WEB",
            },
            headers={"User-Agent": "Mozilla/5.0 Chrome/120.0 Linux"},
        )
        assert res_web.status_code == 200
        token_web = res_web.json()["tokens"]["access_token"]

        sess_res = await client.get(
            "/api/v1/auth/sessions",
            headers={"Authorization": f"Bearer {token_web}"},
        )
        assert sess_res.status_code == 200
        sessions = sess_res.json()
        assert len(sessions) == 2
        assert {s["platform"] for s in sessions} == {"MOBILE", "WEB"}

        # Logging in on MOBILE Device B revokes MOBILE Device A
        res_b = await client.post(
            "/api/v1/auth/login",
            json={
                "email": email,
                "password": password,
                "platform": "MOBILE",
                "device_id": "device_phone_B",
            },
            headers={"User-Agent": "FanSpace iOS App 1.0 (iPhone 15)"},
        )
        assert res_b.status_code == 200

        profile_a = await client.get(
            "/api/v1/users/me",
            headers={"Authorization": f"Bearer {token_a}"},
        )
        assert profile_a.status_code == 401

        profile_web = await client.get(
            "/api/v1/users/me",
            headers={"Authorization": f"Bearer {token_web}"},
        )
        assert profile_web.status_code == 200


@pytest.mark.asyncio
async def test_refresh_token_rotation():
    """Rotates the refresh token on use and invalidates replay of the previous refresh token."""
    transport = ASGITransport(app=app)
    email = f"rotate_{uuid.uuid4().hex[:6]}@example.com"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        reg_data = await _register_verified_user(
            client,
            email=email,
            username=f"rot_{uuid.uuid4().hex[:6]}",
            password="Password123!",
            display_name="Rotation Tester",
        )
        tokens = reg_data["tokens"]
        old_refresh = tokens["refresh_token"]

        ref_res = await client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": old_refresh},
        )
        assert ref_res.status_code == 200
        new_tokens = ref_res.json()
        assert new_tokens["access_token"] != tokens["access_token"]
        assert new_tokens["refresh_token"] != old_refresh

        reuse_res = await client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": old_refresh},
        )
        assert reuse_res.status_code == 401


@pytest.mark.asyncio
async def test_account_deletion():
    """Soft-deletes the user account only when the correct password is provided."""
    transport = ASGITransport(app=app)
    email = f"del_{uuid.uuid4().hex[:6]}@example.com"
    password = "DeleteMePassword123!"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        reg_data = await _register_verified_user(
            client,
            email=email,
            username=f"del_{uuid.uuid4().hex[:6]}",
            password=password,
            display_name="Delete Tester",
        )
        token = reg_data["tokens"]["access_token"]

        bad_del = await client.post(
            "/api/v1/auth/delete-account",
            headers={"Authorization": f"Bearer {token}"},
            json={"password": "WrongPassword!"},
        )
        assert bad_del.status_code == 400

        good_del = await client.post(
            "/api/v1/auth/delete-account",
            headers={"Authorization": f"Bearer {token}"},
            json={"password": password},
        )
        assert good_del.status_code == 200
        assert good_del.json()["success"] is True

