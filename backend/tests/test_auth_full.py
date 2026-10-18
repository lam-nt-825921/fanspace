import uuid
import pytest
from httpx import ASGITransport, AsyncClient
from app.main import app
from app.core.redis import redis_client


@pytest.mark.asyncio
async def test_mobile_device_id_requirement():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # MOBILE platform without device_id must be rejected with 400
        res = await client.post(
            "/api/v1/auth/register",
            json={
                "email": f"mobile_{uuid.uuid4().hex[:6]}@example.com",
                "username": f"mob_{uuid.uuid4().hex[:6]}",
                "password": "Password123!",
                "display_name": "Mobile Tester",
                "platform": "MOBILE",
            },
        )
        assert res.status_code == 400
        assert "mã định danh thiết bị" in res.json()["detail"]


@pytest.mark.asyncio
async def test_single_active_session_per_platform():
    transport = ASGITransport(app=app)
    email = f"user_{uuid.uuid4().hex[:6]}@example.com"
    username = f"u_{uuid.uuid4().hex[:6]}"
    password = "StrongPassword123!"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Register on MOBILE Device A
        res_a = await client.post(
            "/api/v1/auth/register",
            json={
                "email": email,
                "username": username,
                "password": password,
                "display_name": "Multi Device User",
                "platform": "MOBILE",
                "device_id": "device_phone_A",
            },
            headers={"User-Agent": "FanSpace Android App 1.0 (Pixel 7)"},
        )
        assert res_a.status_code == 201
        token_a = res_a.json()["tokens"]["access_token"]
        session_id_a = res_a.json()["tokens"]["session_id"]
        assert res_a.json()["user"]["coin_balance"] == 0  # Rule: No free money!

        # 2. Login on WEB platform
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

        # Check sessions from WEB: should have 2 active sessions (1 MOBILE, 1 WEB)
        sess_res = await client.get(
            "/api/v1/auth/sessions",
            headers={"Authorization": f"Bearer {token_web}"},
        )
        assert sess_res.status_code == 200
        sessions = sess_res.json()
        assert len(sessions) == 2
        platforms = {s["platform"] for s in sessions}
        assert platforms == {"MOBILE", "WEB"}

        # 3. Login on MOBILE Device B -> Must invalidate MOBILE Device A!
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
        token_b = res_b.json()["tokens"]["access_token"]

        # Now, requests using token_a (from Device A) must be rejected because session is revoked
        profile_a = await client.get(
            "/api/v1/users/me",
            headers={"Authorization": f"Bearer {token_a}"},
        )
        assert profile_a.status_code == 401
        assert "đăng xuất" in profile_a.json()["detail"]

        # But WEB session is still alive!
        profile_web = await client.get(
            "/api/v1/users/me",
            headers={"Authorization": f"Bearer {token_web}"},
        )
        assert profile_web.status_code == 200


@pytest.mark.asyncio
async def test_login_lockout_rate_limit():
    transport = ASGITransport(app=app)
    email = f"brute_{uuid.uuid4().hex[:6]}@example.com"
    username = f"brute_{uuid.uuid4().hex[:6]}"
    password = "CorrectPassword123!"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Register user first
        await client.post(
            "/api/v1/auth/register",
            json={
                "email": email,
                "username": username,
                "password": password,
                "display_name": "Target User",
                "platform": "WEB",
            },
        )

        # 5 failed login attempts
        for _ in range(5):
            bad = await client.post(
                "/api/v1/auth/login",
                json={"email": email, "password": "WrongPassword!"},
            )
            assert bad.status_code == 401

        # 6th attempt -> Locked out with 429
        locked = await client.post(
            "/api/v1/auth/login",
            json={"email": email, "password": "WrongPassword!"},
        )
        assert locked.status_code == 429
        assert "khóa bảo vệ" in locked.json()["detail"]

        # Even with correct password, still locked
        locked_correct = await client.post(
            "/api/v1/auth/login",
            json={"email": email, "password": password},
        )
        assert locked_correct.status_code == 429

        # Clean up Redis lockout key
        await redis_client.delete(f"ratelimit:login:failed:{email}")


@pytest.mark.asyncio
async def test_email_otp_verification_flow():
    transport = ASGITransport(app=app)
    email = f"verify_{uuid.uuid4().hex[:6]}@example.com"
    username = f"ver_{uuid.uuid4().hex[:6]}"
    password = "Password123!"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Register unverified user
        reg_res = await client.post(
            "/api/v1/auth/register",
            json={
                "email": email,
                "username": username,
                "password": password,
                "display_name": "Unverified User",
            },
        )
        assert reg_res.status_code == 201
        token = reg_res.json()["tokens"]["access_token"]
        assert reg_res.json()["user"]["is_email_verified"] is False

        # Request OTP
        otp_res = await client.post(
            "/api/v1/auth/email/send-otp",
            json={"email": email, "purpose": "VERIFY_EMAIL"},
        )
        assert otp_res.status_code == 200
        otp_data = otp_res.json()
        assert "dev_otp" in otp_data
        otp_code = otp_data["dev_otp"]

        # Request again immediately -> 429 Cooldown
        spam_res = await client.post(
            "/api/v1/auth/email/send-otp",
            json={"email": email, "purpose": "VERIFY_EMAIL"},
        )
        assert spam_res.status_code == 429
        assert "Vui lòng đợi" in spam_res.json()["detail"]

        # Test wrong OTP attempt
        bad_verify = await client.post(
            "/api/v1/auth/email/verify-otp",
            json={"email": email, "code": "000000", "purpose": "VERIFY_EMAIL"},
        )
        assert bad_verify.status_code == 400
        assert "Mã OTP không chính xác" in bad_verify.json()["detail"]

        # Verify with right OTP
        good_verify = await client.post(
            "/api/v1/auth/email/verify-otp",
            json={"email": email, "code": otp_code, "purpose": "VERIFY_EMAIL"},
        )
        assert good_verify.status_code == 200
        assert good_verify.json()["success"] is True

        # Check /me -> is_email_verified should now be True
        me_res = await client.get(
            "/api/v1/users/me",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert me_res.status_code == 200
        assert me_res.json()["is_email_verified"] is True


@pytest.mark.asyncio
async def test_google_oauth_auto_linking():
    transport = ASGITransport(app=app)
    shared_email = f"shared_{uuid.uuid4().hex[:6]}@gmail.com"
    username = f"manual_{uuid.uuid4().hex[:6]}"
    password = "ManualPassword123!"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. User registers standard account with password
        reg_res = await client.post(
            "/api/v1/auth/register",
            json={
                "email": shared_email,
                "username": username,
                "password": password,
                "display_name": "Standard User",
            },
        )
        assert reg_res.status_code == 201
        assert reg_res.json()["user"]["is_google_linked"] is False

        # 2. User later signs in via Google using same email -> Auto-link!
        google_res = await client.post(
            "/api/v1/auth/google",
            json={
                "email": shared_email,
                "display_name": "Google Name",
                "avatar_url": "https://avatar.google/photo.jpg",
            },
        )
        assert google_res.status_code == 200
        google_data = google_res.json()
        assert google_data["success"] is True
        assert google_data["user"]["email"] == shared_email
        assert google_data["user"]["username"] == username  # Kept existing user!
        assert google_data["user"]["is_google_linked"] is True
        assert google_data["user"]["is_email_verified"] is True
        assert google_data["user"]["has_password"] is True


@pytest.mark.asyncio
async def test_oauth_user_set_password_flow():
    transport = ASGITransport(app=app)
    google_email = f"googleonly_{uuid.uuid4().hex[:6]}@gmail.com"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Pure Google login (creates new user with password_hash=None)
        google_res = await client.post(
            "/api/v1/auth/google",
            json={"email": google_email, "display_name": "Pure Google Fan"},
        )
        assert google_res.status_code == 200
        token = google_res.json()["tokens"]["access_token"]
        assert google_res.json()["user"]["has_password"] is False

        # 2. Request OTP to set password
        otp_res = await client.post(
            "/api/v1/auth/email/send-otp",
            json={"email": google_email, "purpose": "OAUTH_SET_PASSWORD"},
        )
        assert otp_res.status_code == 200
        otp_code = otp_res.json()["dev_otp"]

        # 3. Set password using OTP
        set_res = await client.post(
            "/api/v1/auth/password/oauth-set",
            headers={"Authorization": f"Bearer {token}"},
            json={"otp": otp_code, "new_password": "NewCreatedPassword123!"},
        )
        assert set_res.status_code == 200
        assert set_res.json()["success"] is True

        # 4. Check user profile
        me_res = await client.get(
            "/api/v1/users/me",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert me_res.json()["has_password"] is True

        # 5. User can now login with email + newly set password!
        login_res = await client.post(
            "/api/v1/auth/login",
            json={"email": google_email, "password": "NewCreatedPassword123!"},
        )
        assert login_res.status_code == 200
        assert login_res.json()["success"] is True


@pytest.mark.asyncio
async def test_refresh_token_rotation():
    transport = ASGITransport(app=app)
    email = f"rotate_{uuid.uuid4().hex[:6]}@example.com"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        reg_res = await client.post(
            "/api/v1/auth/register",
            json={
                "email": email,
                "username": f"rot_{uuid.uuid4().hex[:6]}",
                "password": "Password123!",
                "display_name": "Rotation Tester",
            },
        )
        tokens = reg_res.json()["tokens"]
        old_refresh = tokens["refresh_token"]

        # Call /refresh
        ref_res = await client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": old_refresh},
        )
        assert ref_res.status_code == 200
        new_tokens = ref_res.json()
        assert new_tokens["access_token"] != tokens["access_token"]
        assert new_tokens["refresh_token"] != old_refresh

        # Attempt to reuse old_refresh token -> 401 Unauthorized
        reuse_res = await client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": old_refresh},
        )
        assert reuse_res.status_code == 401


@pytest.mark.asyncio
async def test_account_deletion():
    transport = ASGITransport(app=app)
    email = f"del_{uuid.uuid4().hex[:6]}@example.com"
    password = "DeleteMePassword123!"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        reg_res = await client.post(
            "/api/v1/auth/register",
            json={
                "email": email,
                "username": f"del_{uuid.uuid4().hex[:6]}",
                "password": password,
                "display_name": "Delete Tester",
            },
        )
        token = reg_res.json()["tokens"]["access_token"]

        # Delete with wrong password
        bad_del = await client.post(
            "/api/v1/auth/delete-account",
            headers={"Authorization": f"Bearer {token}"},
            json={"password": "WrongPassword!"},
        )
        assert bad_del.status_code == 400

        # Delete with correct password
        good_del = await client.post(
            "/api/v1/auth/delete-account",
            headers={"Authorization": f"Bearer {token}"},
            json={"password": password},
        )
        assert good_del.status_code == 200
        assert good_del.json()["success"] is True

        # Session should now be dead
        me_res = await client.get(
            "/api/v1/users/me",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert me_res.status_code == 401
