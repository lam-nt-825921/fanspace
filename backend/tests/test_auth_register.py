"""Integration tests for staged user registration and OTP email verification.

Covers:
- Two-step registration workflow (Redis staging + SMTP OTP dispatch -> PostgreSQL user provisioning).
- Required field validation (`email`, `username`, `password`, `display_name`, and mobile `device_id`).
- Field format validation, uniqueness checks, and temporary username reservation in Redis.
- Staged registration TTL expiration, 5-attempt OTP brute-force cancellation, and IP rate limiting.
- Outgoing SMTP payload verification and live Gmail SMTP TLS authentication.
"""

import uuid
import aiosmtplib
import pytest
from httpx import ASGITransport, AsyncClient
from app.main import app
from app.core.config import get_settings
from app.core.redis import get_redis_client

settings = get_settings()


# ==============================================================================
# 1. STAGED REGISTRATION & OTP VERIFICATION WORKFLOW
# ==============================================================================


@pytest.mark.asyncio
async def test_register_staged_and_verified_minimal_fields(mock_smtp_send):
    """Stages registration in Redis, dispatches an OTP email, and provisions the user only after OTP verification."""
    transport = ASGITransport(app=app)
    uid = uuid.uuid4().hex[:8]
    email = f"valid_min_{uid}@example.com"
    username = f"user_min_{uid}"
    password = "ValidPassword123!"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Step 1: Stage registration in Redis and dispatch OTP email
        reg_res = await client.post(
            "/api/v1/auth/register",
            json={
                "email": email,
                "username": username,
                "password": password,
                "display_name": "Người Dùng Hợp Lệ",
            },
        )
        assert reg_res.status_code == 202
        reg_data = reg_res.json()
        assert reg_data["success"] is True
        assert reg_data["require_otp"] is True
        assert reg_data["email"] == email
        assert reg_data["expires_in_seconds"] == settings.PENDING_REGISTRATION_TTL_SECONDS
        assert "tokens" not in reg_data
        otp_code = reg_data["dev_otp"]
        assert otp_code and len(otp_code) == 6

        # Verify SMTP dispatch recipient and subject
        assert mock_smtp_send.called
        sent_msg = mock_smtp_send.call_args[0][0]
        assert sent_msg["To"] == email
        assert otp_code in sent_msg["Subject"]

        # Verify user does not exist in PostgreSQL prior to OTP verification
        premature_login = await client.post(
            "/api/v1/auth/login",
            json={"email": email, "password": password},
        )
        assert premature_login.status_code == 401

        # Step 2: Verify OTP to provision the User, Wallet, and Session in PostgreSQL
        verify_res = await client.post(
            "/api/v1/auth/email/verify-otp",
            json={"email": email, "code": otp_code, "purpose": "VERIFY_EMAIL"},
        )
        assert verify_res.status_code == 200
        v_data = verify_res.json()
        assert v_data["success"] is True
        assert v_data["tokens"]["access_token"]
        assert v_data["tokens"]["refresh_token"]
        assert v_data["user"]["email"] == email
        assert v_data["user"]["username"] == username
        assert v_data["user"]["display_name"] == "Người Dùng Hợp Lệ"
        assert v_data["user"]["coin_balance"] == 0
        assert v_data["user"]["is_email_verified"] is True
        assert v_data["user"]["has_password"] is True
        assert v_data["user"]["is_google_linked"] is False

        # Verify temporary Redis keys are cleaned up after account creation
        r = get_redis_client()
        assert await r.get(f"pending_reg:email:{email}") is None
        assert await r.get(f"pending_reg:username:{username.lower()}") is None


@pytest.mark.asyncio
async def test_register_staged_and_verified_full_mobile_fields():
    """Completes staged registration and OTP verification when optional mobile platform metadata is provided."""
    transport = ASGITransport(app=app)
    uid = uuid.uuid4().hex[:8]
    email = f"valid_full_{uid}@example.com"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        reg_res = await client.post(
            "/api/v1/auth/register",
            json={
                "email": email,
                "username": f"user-full_{uid}",
                "password": "StrongPassword999!",
                "display_name": "Mobile Full User",
                "platform": "MOBILE",
                "device_id": f"android_hw_{uid}",
            },
            headers={"User-Agent": "FanSpace Android/1.0"},
        )
        assert reg_res.status_code == 202
        otp_code = reg_res.json()["dev_otp"]

        verify_res = await client.post(
            "/api/v1/auth/email/verify-otp",
            json={"email": email, "code": otp_code, "purpose": "VERIFY_EMAIL"},
        )
        assert verify_res.status_code == 200
        data = verify_res.json()
        assert data["success"] is True
        assert data["tokens"]["session_id"] is not None


# ==============================================================================
# 2. MISSING REQUIRED FIELDS
# ==============================================================================


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "missing_field",
    ["email", "username", "password", "display_name"],
)
async def test_register_missing_each_required_field(missing_field: str):
    """Rejects registration requests missing any required field with 422 Unprocessable Entity."""
    transport = ASGITransport(app=app)
    uid = uuid.uuid4().hex[:6]
    payload = {
        "email": f"miss_{uid}@example.com",
        "username": f"miss_{uid}",
        "password": "Password123!",
        "display_name": "Missing Field Tester",
    }
    payload.pop(missing_field)

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        res = await client.post("/api/v1/auth/register", json=payload)
        assert res.status_code == 422
        errors = res.json()["detail"]
        assert any(missing_field in err["loc"] for err in errors)


@pytest.mark.asyncio
async def test_register_empty_payload():
    """Rejects an empty registration payload with 422 Unprocessable Entity."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        res = await client.post("/api/v1/auth/register", json={})
        assert res.status_code == 422
        assert len(res.json()["detail"]) >= 4


@pytest.mark.asyncio
async def test_register_mobile_missing_device_id():
    """Rejects mobile registration requests that omit device_id with 400 Bad Request."""
    transport = ASGITransport(app=app)
    uid = uuid.uuid4().hex[:6]
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        res = await client.post(
            "/api/v1/auth/register",
            json={
                "email": f"mobile_{uid}@example.com",
                "username": f"mob_{uid}",
                "password": "Password123!",
                "display_name": "Mobile Tester",
                "platform": "MOBILE",
            },
        )
        assert res.status_code == 400
        assert "mã định danh thiết bị" in res.json()["detail"]


# ==============================================================================
# 3. FIELD FORMAT VALIDATION, UNIQUENESS & USERNAME RESERVATION
# ==============================================================================


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "invalid_payload_override,expected_field",
    [
        ({"email": "not-an-email"}, "email"),
        ({"email": "@missing-local.com"}, "email"),
        ({"email": ""}, "email"),
        ({"username": "ab"}, "username"),
        ({"username": "a" * 51}, "username"),
        ({"username": "bad space"}, "username"),
        ({"username": "bad@char!"}, "username"),
        ({"password": "12345"}, "password"),
        ({"password": "p" * 101}, "password"),
        ({"display_name": ""}, "display_name"),
        ({"display_name": "d" * 101}, "display_name"),
    ],
)
async def test_register_invalid_field_formats(invalid_payload_override: dict, expected_field: str):
    """Rejects invalid email, username, password, and display_name formats with 422 Unprocessable Entity."""
    transport = ASGITransport(app=app)
    uid = uuid.uuid4().hex[:6]
    base_payload = {
        "email": f"valid_{uid}@example.com",
        "username": f"valid_{uid}",
        "password": "ValidPassword123!",
        "display_name": "Valid Display Name",
    }
    base_payload.update(invalid_payload_override)

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        res = await client.post("/api/v1/auth/register", json=base_payload)
        assert res.status_code == 422
        errors = res.json()["detail"]
        assert any(expected_field in err["loc"] for err in errors)


@pytest.mark.asyncio
async def test_register_duplicate_email_and_duplicate_username():
    """Rejects registration attempts using an already-registered email or username with 400 Bad Request."""
    transport = ASGITransport(app=app)
    uid = uuid.uuid4().hex[:6]
    email = f"dup_{uid}@example.com"
    username = f"dup_user_{uid}"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        first_res = await client.post(
            "/api/v1/auth/register",
            json={
                "email": email,
                "username": username,
                "password": "Password123!",
                "display_name": "Original User",
            },
        )
        assert first_res.status_code == 202
        otp_code = first_res.json()["dev_otp"]
        verify_res = await client.post(
            "/api/v1/auth/email/verify-otp",
            json={"email": email, "code": otp_code, "purpose": "VERIFY_EMAIL"},
        )
        assert verify_res.status_code == 200

        # Duplicate email with a different username -> 400
        dup_email_res = await client.post(
            "/api/v1/auth/register",
            json={
                "email": email,
                "username": f"other_user_{uid}",
                "password": "Password123!",
                "display_name": "Dup Email User",
            },
        )
        assert dup_email_res.status_code == 400
        assert "đã được sử dụng" in dup_email_res.json()["detail"]

        # Duplicate username with a different email -> 400
        dup_user_res = await client.post(
            "/api/v1/auth/register",
            json={
                "email": f"other_{uid}@example.com",
                "username": username,
                "password": "Password123!",
                "display_name": "Dup Username User",
            },
        )
        assert dup_user_res.status_code == 400
        assert "đã được sử dụng" in dup_user_res.json()["detail"]


@pytest.mark.asyncio
async def test_register_username_reservation_and_auto_release_on_expiry():
    """Reserves a staged username in Redis during pending OTP verification and releases it upon TTL expiry."""
    transport = ASGITransport(app=app)
    uid = uuid.uuid4().hex[:6]
    hot_username = f"idol_{uid}"
    email_a = f"user_a_{uid}@example.com"
    email_b = f"user_b_{uid}@example.com"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        res_a = await client.post(
            "/api/v1/auth/register",
            json={
                "email": email_a,
                "username": hot_username,
                "password": "Password123!",
                "display_name": "User A",
            },
        )
        assert res_a.status_code == 202

        # Another user cannot claim the reserved username while User A's pending registration is active -> 400
        res_b_blocked = await client.post(
            "/api/v1/auth/register",
            json={
                "email": email_b,
                "username": hot_username,
                "password": "Password123!",
                "display_name": "User B",
            },
        )
        assert res_b_blocked.status_code == 400
        assert "đang được giữ chỗ" in res_b_blocked.json()["detail"]

        # Simulate TTL expiration of User A's staged registration in Redis
        r = get_redis_client()
        await r.delete(f"pending_reg:email:{email_a}")
        await r.delete(f"pending_reg:username:{hot_username.lower()}")

        # User B can now claim the released username -> 202 Accepted
        res_b_ok = await client.post(
            "/api/v1/auth/register",
            json={
                "email": email_b,
                "username": hot_username,
                "password": "Password123!",
                "display_name": "User B",
            },
        )
        assert res_b_ok.status_code == 202


# ==============================================================================
# 4. TTL EXPIRATION, BRUTE-FORCE CANCELLATION & ANTI-SPAM LIMITS
# ==============================================================================


@pytest.mark.asyncio
async def test_register_auto_cancel_after_ttl_expiration():
    """Rejects OTP verification with 400 Bad Request when the staged registration TTL has expired."""
    transport = ASGITransport(app=app)
    uid = uuid.uuid4().hex[:6]
    email = f"expired_{uid}@example.com"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        reg_res = await client.post(
            "/api/v1/auth/register",
            json={
                "email": email,
                "username": f"exp_{uid}",
                "password": "Password123!",
                "display_name": "Expired User",
            },
        )
        assert reg_res.status_code == 202
        otp_code = reg_res.json()["dev_otp"]

        r = get_redis_client()
        await r.delete(f"pending_reg:email:{email}")

        verify_res = await client.post(
            "/api/v1/auth/email/verify-otp",
            json={"email": email, "code": otp_code, "purpose": "VERIFY_EMAIL"},
        )
        assert verify_res.status_code == 400
        assert "tự hủy" in verify_res.json()["detail"] or "hết hạn" in verify_res.json()["detail"]


@pytest.mark.asyncio
async def test_register_otp_brute_force_5_strikes_cancels_pending_registration():
    """Cancels both the OTP and the staged registration in Redis after 5 consecutive failed OTP attempts."""
    transport = ASGITransport(app=app)
    uid = uuid.uuid4().hex[:6]
    email = f"bf_otp_{uid}@example.com"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        reg_res = await client.post(
            "/api/v1/auth/register",
            json={
                "email": email,
                "username": f"bf_{uid}",
                "password": "Password123!",
                "display_name": "Brute Force OTP User",
            },
        )
        assert reg_res.status_code == 202
        real_otp = reg_res.json()["dev_otp"]

        for _ in range(5):
            bad_res = await client.post(
                "/api/v1/auth/email/verify-otp",
                json={"email": email, "code": "000000", "purpose": "VERIFY_EMAIL"},
            )
            assert bad_res.status_code == 400

        r = get_redis_client()
        assert await r.get(f"pending_reg:email:{email}") is None

        # Subsequent attempt with the original OTP is rejected because the staged registration was purged
        late_res = await client.post(
            "/api/v1/auth/email/verify-otp",
            json={"email": email, "code": real_otp, "purpose": "VERIFY_EMAIL"},
        )
        assert late_res.status_code == 400


@pytest.mark.asyncio
async def test_send_otp_rejects_unrequested_random_email():
    """Rejects OTP dispatch requests for emails that have no active account or pending registration."""
    transport = ASGITransport(app=app)
    random_email = f"random_victim_{uuid.uuid4().hex[:6]}@gmail.com"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        res_verify = await client.post(
            "/api/v1/auth/email/send-otp",
            json={"email": random_email, "purpose": "VERIFY_EMAIL"},
        )
        assert res_verify.status_code == 400

        res_reset = await client.post(
            "/api/v1/auth/email/send-otp",
            json={"email": random_email, "purpose": "RESET_PASSWORD"},
        )
        assert res_reset.status_code == 400


@pytest.mark.asyncio
async def test_register_ip_rate_limit():
    """Enforces a maximum of 5 registration initializations per IP within 10 minutes, returning 429 on the 6th."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        for i in range(5):
            uid = uuid.uuid4().hex[:6]
            res = await client.post(
                "/api/v1/auth/register",
                json={
                    "email": f"rate_{i}_{uid}@example.com",
                    "username": f"rate_{i}_{uid}",
                    "password": "Password123!",
                    "display_name": f"Rate User {i}",
                },
            )
            assert res.status_code == 202

        uid6 = uuid.uuid4().hex[:6]
        res_6 = await client.post(
            "/api/v1/auth/register",
            json={
                "email": f"rate_6_{uid6}@example.com",
                "username": f"rate_6_{uid6}",
                "password": "Password123!",
                "display_name": "Rate User 6",
            },
        )
        assert res_6.status_code == 429


# ==============================================================================
# 5. LIVE GMAIL SMTP AUTHENTICATION CHECK
# ==============================================================================


@pytest.mark.asyncio
async def test_gmail_smtp_live_authentication():
    """Verifies live STARTTLS connection and login against the configured SMTP server."""
    if not settings.SMTP_USER or not settings.SMTP_PASSWORD:
        pytest.skip("SMTP_USER or SMTP_PASSWORD is not configured in environment.")

    smtp = aiosmtplib.SMTP(
        hostname=settings.SMTP_HOST,
        port=settings.SMTP_PORT,
        start_tls=True,
        timeout=10.0,
    )
    await smtp.connect()
    auth_response = await smtp.login(settings.SMTP_USER, settings.SMTP_PASSWORD)
    await smtp.quit()
    assert auth_response.code == 235

