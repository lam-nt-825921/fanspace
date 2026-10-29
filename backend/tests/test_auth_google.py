"""Dedicated Unit & Integration Tests for Google OAuth2 Authentication (FR-01).

Uses real RSA-2048 cryptographic key pairs (`cryptography` + `google.auth.jwt.encode`)
and Google's official `google.oauth2.id_token.verify_oauth2_token` verifier against local
JWKS certificates (`_fetch_certs`).

Covers:
1. Missing fields:
   - Empty payload `{}` (422).
   - Email-only payload without `id_token` (422).
   - `platform="MOBILE"` without `device_id` (400).
2. Invalid / Forged tokens:
   - `id_token` shorter than minimum length (422).
   - Malformed non-JWT string (401).
   - Forged RSA-256 signature signed by an attacker's private key (401).
   - Wrong Client ID audience (`aud`) (401).
   - Expired token (`exp` in the past) (401).
   - Invalid issuer (`iss` not `accounts.google.com`) (401).
   - Unverified Google email (`email_verified=False`) (401).
3. Valid Google OAuth2 flows:
   - First-time Google login auto-provisioning an account (`has_password=False`) + establishing password via OTP.
   - Google login matching an existing verified email account (`test_google_oauth_auto_linking`).
"""

import time
import uuid
from unittest.mock import patch
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from google.auth import crypt as google_crypt
from google.auth import jwt as google_jwt
from httpx import ASGITransport, AsyncClient

from app.main import app
from app.core.config import get_settings

settings = get_settings()

TEST_GOOGLE_CLIENT_ID = "test-fanspace-client-id.apps.googleusercontent.com"
TEST_GOOGLE_KEY_ID = "google_test_rsa_kid_2026"


def _generate_rsa_keypair() -> tuple[bytes, str]:
    """Sinh cặp khóa RSA-2048 (Private PEM & Public PEM) phục vụ ký JWT thật trong kiểm thử."""
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    private_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    public_pem = (
        private_key.public_key()
        .public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        )
        .decode("utf-8")
    )
    return private_pem, public_pem


_GOOGLE_PRIVATE_PEM, _GOOGLE_PUBLIC_PEM = _generate_rsa_keypair()
_ATTACKER_PRIVATE_PEM, _ = _generate_rsa_keypair()


def create_signed_google_id_token(
    *,
    sub: str,
    email: str,
    aud: str = TEST_GOOGLE_CLIENT_ID,
    iss: str = "https://accounts.google.com",
    email_verified: bool = True,
    name: str = "Google Test User",
    picture: str = "https://lh3.googleusercontent.com/a/default-user",
    exp_offset_seconds: int = 3600,
    private_pem: bytes = _GOOGLE_PRIVATE_PEM,
    key_id: str = TEST_GOOGLE_KEY_ID,
) -> str:
    """Tạo Google JWT ID Token được ký số RSA-256 thật bằng `google.auth.jwt.encode`."""
    now = int(time.time())
    claims = {
        "iss": iss,
        "aud": aud,
        "sub": sub,
        "email": email,
        "email_verified": email_verified,
        "name": name,
        "picture": picture,
        "iat": now - 60,
        "exp": now + exp_offset_seconds,
    }
    signer = google_crypt.RSASigner.from_string(private_pem, key_id=key_id)
    encoded = google_jwt.encode(signer, claims)
    return encoded.decode("utf-8") if isinstance(encoded, bytes) else encoded


@pytest.fixture
def mock_google_certs(monkeypatch):
    """Cấu hình GOOGLE_CLIENT_ID và cung cấp chứng chỉ RSA Public Key cho `google.oauth2.id_token._fetch_certs`."""
    monkeypatch.setattr(settings, "GOOGLE_CLIENT_ID", TEST_GOOGLE_CLIENT_ID)
    with patch(
        "google.oauth2.id_token._fetch_certs",
        return_value={TEST_GOOGLE_KEY_ID: _GOOGLE_PUBLIC_PEM},
    ) as mock_certs:
        yield mock_certs


# ==============================================================================
# 1. THIẾU TRƯỜNG & SAI TRƯỜNG / GIẢ MẠO TOKEN (MISSING & INVALID GOOGLE TOKENS)
# ==============================================================================


@pytest.mark.asyncio
async def test_google_login_missing_and_invalid_fields(mock_google_certs, monkeypatch):
    """Kiểm tra đầy đủ các case thiếu trường và sai trường/giả mạo chữ ký RSA của Google OAuth2."""
    monkeypatch.setattr(settings, "DEBUG", True)
    transport = ASGITransport(app=app)
    victim_email = f"victim_{uuid.uuid4().hex[:6]}@gmail.com"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Thiếu trường: Body rỗng {} -> 422
        res_empty = await client.post("/api/v1/auth/google", json={})
        assert res_empty.status_code == 422

        # 2. Thiếu trường: Chỉ gửi email mà không có id_token (lỗ hổng cũ) -> 422
        res_email_only = await client.post(
            "/api/v1/auth/google",
            json={"email": victim_email, "display_name": "Attacker"},
        )
        assert res_email_only.status_code == 422

        # 3. Sai trường: id_token quá ngắn (< 10 ký tự) -> 422
        res_short = await client.post(
            "/api/v1/auth/google",
            json={"id_token": "short"},
        )
        assert res_short.status_code == 422

        # 4. Sai trường: id_token là chuỗi rác không đúng cấu trúc JWT -> 401
        res_garbage = await client.post(
            "/api/v1/auth/google",
            json={"id_token": "not_a_valid_jwt_token_at_all_12345"},
        )
        assert res_garbage.status_code == 401

        # 5. Sai chữ ký số RSA: Token ký bằng Private Key của kẻ tấn công (không khớp JWKS của Google) -> 401
        forged_rsa_token = create_signed_google_id_token(
            sub="google_sub_victim",
            email=victim_email,
            private_pem=_ATTACKER_PRIVATE_PEM,
        )
        res_forged_sig = await client.post(
            "/api/v1/auth/google",
            json={"id_token": forged_rsa_token, "email": victim_email},
        )
        assert res_forged_sig.status_code == 401

        # 6. Sai Audience (aud): Token ký đúng khóa Google nhưng cấp cho Client ID của ứng dụng khác -> 401
        wrong_aud_token = create_signed_google_id_token(
            sub="google_sub_victim",
            email=victim_email,
            aud="other-app-client-id.apps.googleusercontent.com",
        )
        res_wrong_aud = await client.post(
            "/api/v1/auth/google",
            json={"id_token": wrong_aud_token},
        )
        assert res_wrong_aud.status_code == 401

        # 7. Token đã hết hạn (exp < now) -> 401
        expired_token = create_signed_google_id_token(
            sub="google_sub_victim",
            email=victim_email,
            exp_offset_seconds=-300,
        )
        res_expired = await client.post(
            "/api/v1/auth/google",
            json={"id_token": expired_token},
        )
        assert res_expired.status_code == 401

        # 8. Sai Issuer (iss không phải accounts.google.com) -> 401
        wrong_iss_token = create_signed_google_id_token(
            sub="google_sub_victim",
            email=victim_email,
            iss="https://evil-issuer.example.com",
        )
        res_wrong_iss = await client.post(
            "/api/v1/auth/google",
            json={"id_token": wrong_iss_token},
        )
        assert res_wrong_iss.status_code == 401

        # 9. Email Google chưa được xác minh (email_verified = False) -> 401
        unverified_email_token = create_signed_google_id_token(
            sub="google_sub_unverified",
            email=victim_email,
            email_verified=False,
        )
        res_unverified = await client.post(
            "/api/v1/auth/google",
            json={"id_token": unverified_email_token},
        )
        assert res_unverified.status_code == 401

        # 10. Thiếu device_id khi đăng nhập Google trên nền tảng MOBILE -> 400
        valid_token = create_signed_google_id_token(
            sub="google_sub_mob",
            email=victim_email,
        )
        res_mob_no_device = await client.post(
            "/api/v1/auth/google",
            json={"id_token": valid_token, "platform": "MOBILE"},
        )
        assert res_mob_no_device.status_code == 400


# ==============================================================================
# 2. CASE ĐỦ TRƯỜNG HỢP LỆ — ĐĂNG NHẬP GOOGLE, LIÊN KẾT & ĐẶT MẬT KHẨU QUA OTP
# ==============================================================================


@pytest.mark.asyncio
async def test_google_oauth_auto_linking(mock_google_certs):
    """Đăng nhập Google bằng ID Token ký số RSA hợp lệ khi trùng email đã tồn tại."""
    transport = ASGITransport(app=app)
    shared_email = f"shared_{uuid.uuid4().hex[:6]}@gmail.com"
    username = f"manual_{uuid.uuid4().hex[:6]}"
    password = "ManualPassword123!"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Người dùng đăng ký tài khoản bằng email & mật khẩu (qua 2 bước OTP)
        reg_res = await client.post(
            "/api/v1/auth/register",
            json={
                "email": shared_email,
                "username": username,
                "password": password,
                "display_name": "Standard User",
            },
        )
        assert reg_res.status_code == 202
        otp_code = reg_res.json()["dev_otp"]
        verify_res = await client.post(
            "/api/v1/auth/email/verify-otp",
            json={"email": shared_email, "code": otp_code, "purpose": "VERIFY_EMAIL"},
        )
        assert verify_res.status_code == 200
        assert verify_res.json()["user"]["is_google_linked"] is False

        # 2. Người dùng đăng nhập qua Google với ID Token RSA hợp lệ
        valid_google_token = create_signed_google_id_token(
            sub=f"google_sub_{shared_email}",
            email=shared_email,
            name="Google Name",
            picture="https://avatar.google/photo.jpg",
        )
        google_res = await client.post(
            "/api/v1/auth/google",
            json={
                "id_token": valid_google_token,
                "platform": "MOBILE",
                "device_id": "pixel_8_pro",
            },
        )
        assert google_res.status_code == 200
        google_data = google_res.json()
        assert google_data["success"] is True
        assert google_data["user"]["email"] == shared_email
        assert google_data["user"]["username"] == username
        assert google_data["user"]["is_google_linked"] is True
        assert google_data["user"]["is_email_verified"] is True
        assert google_data["user"]["has_password"] is True


@pytest.mark.asyncio
async def test_oauth_user_set_password_flow(mock_google_certs):
    """Đăng nhập Google lần đầu (tự sinh tài khoản chưa có mật khẩu) và thiết lập mật khẩu qua OTP."""
    transport = ASGITransport(app=app)
    google_email = f"googleonly_{uuid.uuid4().hex[:6]}@gmail.com"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Đăng nhập Google bằng ID Token RSA hợp lệ -> Tạo user mới với has_password=False
        valid_google_token = create_signed_google_id_token(
            sub=f"google_sub_{google_email}",
            email=google_email,
            name="Pure Google Fan",
        )
        google_res = await client.post(
            "/api/v1/auth/google",
            json={"id_token": valid_google_token},
        )
        assert google_res.status_code == 200
        token = google_res.json()["tokens"]["access_token"]
        assert google_res.json()["user"]["has_password"] is False

        # 2. Yêu cầu gửi OTP để thiết lập mật khẩu
        otp_res = await client.post(
            "/api/v1/auth/email/send-otp",
            json={"email": google_email, "purpose": "OAUTH_SET_PASSWORD"},
        )
        assert otp_res.status_code == 200
        otp_code = otp_res.json()["dev_otp"]

        # 3. Đặt mật khẩu mới bằng OTP
        set_res = await client.post(
            "/api/v1/auth/password/oauth-set",
            headers={"Authorization": f"Bearer {token}"},
            json={"otp": otp_code, "new_password": "NewCreatedPassword123!"},
        )
        assert set_res.status_code == 200
        assert set_res.json()["success"] is True

        # 4. Kiểm tra hồ sơ -> has_password = True
        me_res = await client.get(
            "/api/v1/users/me",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert me_res.json()["has_password"] is True

        # 5. Đăng nhập bằng Email + Mật khẩu vừa đặt
        login_res = await client.post(
            "/api/v1/auth/login",
            json={"email": google_email, "password": "NewCreatedPassword123!"},
        )
        assert login_res.status_code == 200
        assert login_res.json()["success"] is True
