"""Integration tests for Google OAuth2 authentication and account linking flows.

Verifies cryptographic JWT verification using RSA-2048 key pairs and covers:
- Missing, malformed, expired, and forged Google ID tokens.
- Authenticated account linking (`POST /api/v1/auth/google/link`).
- Password-verified account linking when logging in via Google with an existing unlinked email.
- Automatic account provisioning for new Google users and OTP-verified password setup.
- Rejection of password-based login for OAuth-only accounts prior to password setup.
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
    """Generates an RSA-2048 private/public PEM key pair for signing test JWT tokens."""
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
    """Signs a Google OAuth2 ID token payload with the given RSA private key."""
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
    """Configures GOOGLE_CLIENT_ID and stubs Google JWKS public certificate lookup."""
    monkeypatch.setattr(settings, "GOOGLE_CLIENT_ID", TEST_GOOGLE_CLIENT_ID)
    with patch(
        "google.oauth2.id_token._fetch_certs",
        return_value={TEST_GOOGLE_KEY_ID: _GOOGLE_PUBLIC_PEM},
    ) as mock_certs:
        yield mock_certs


async def _register_verified_email_user(
    client: AsyncClient,
    *,
    email: str,
    username: str,
    password: str,
) -> dict:
    """Completes staged registration and OTP verification to provision an Email/Password user."""
    reg_res = await client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "username": username,
            "password": password,
            "display_name": "Standard Email User",
        },
    )
    assert reg_res.status_code == 202
    otp_code = reg_res.json()["dev_otp"]

    verify_res = await client.post(
        "/api/v1/auth/email/verify-otp",
        json={"email": email, "code": otp_code, "purpose": "VERIFY_EMAIL"},
    )
    assert verify_res.status_code == 200
    return verify_res.json()


# ==============================================================================
# 1. TOKEN VALIDATION & PAYLOAD CONSTRAINTS
# ==============================================================================


@pytest.mark.asyncio
async def test_google_login_missing_and_invalid_fields(mock_google_certs, monkeypatch):
    """Rejects missing fields, malformed tokens, forged RSA signatures, invalid claims, and missing mobile device_id."""
    monkeypatch.setattr(settings, "DEBUG", True)
    transport = ASGITransport(app=app)
    victim_email = f"victim_{uuid.uuid4().hex[:6]}@gmail.com"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Empty request payload -> 422
        res_empty = await client.post("/api/v1/auth/google", json={})
        assert res_empty.status_code == 422

        # Missing required id_token field -> 422
        res_email_only = await client.post(
            "/api/v1/auth/google",
            json={"email": victim_email, "display_name": "Attacker"},
        )
        assert res_email_only.status_code == 422

        # id_token shorter than minimum length -> 422
        res_short = await client.post(
            "/api/v1/auth/google",
            json={"id_token": "short"},
        )
        assert res_short.status_code == 422

        # Malformed non-JWT token string -> 401
        res_garbage = await client.post(
            "/api/v1/auth/google",
            json={"id_token": "not_a_valid_jwt_token_at_all_12345"},
        )
        assert res_garbage.status_code == 401

        # Token signed with an untrusted RSA private key -> 401
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

        # Token issued for a different OAuth Client ID (aud mismatch) -> 401
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

        # Expired ID token (exp < current time) -> 401
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

        # Untrusted token issuer (iss mismatch) -> 401
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

        # Unverified Google email address (email_verified=False) -> 401
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

        # Missing device_id when platform is MOBILE -> 400
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
# 2. AUTHENTICATED GOOGLE ACCOUNT LINKING
# ==============================================================================


@pytest.mark.asyncio
async def test_google_link_authenticated_account(mock_google_certs):
    """Allows an authenticated user to link a matching Google account and rejects invalid link requests."""
    transport = ASGITransport(app=app)
    uid = uuid.uuid4().hex[:6]
    email = f"link_user_{uid}@gmail.com"
    other_email = f"link_other_{uid}@gmail.com"
    password = "MyStrongPassword123!"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        reg_data = await _register_verified_email_user(
            client,
            email=email,
            username=f"link_{uid}",
            password=password,
        )
        access_token = reg_data["tokens"]["access_token"]
        assert reg_data["user"]["is_google_linked"] is False

        # Unauthenticated request -> 401
        valid_token = create_signed_google_id_token(
            sub=f"google_sub_link_{uid}",
            email=email,
        )
        unauth_res = await client.post(
            "/api/v1/auth/google/link",
            json={"id_token": valid_token},
        )
        assert unauth_res.status_code == 401

        # Google email does not match the authenticated account's email -> 400
        mismatched_token = create_signed_google_id_token(
            sub=f"google_sub_mismatch_{uid}",
            email=other_email,
        )
        mismatch_res = await client.post(
            "/api/v1/auth/google/link",
            headers={"Authorization": f"Bearer {access_token}"},
            json={"id_token": mismatched_token},
        )
        assert mismatch_res.status_code == 400
        assert "trùng khớp" in mismatch_res.json()["detail"]

        # Matching Google email links successfully -> 200 OK
        link_res = await client.post(
            "/api/v1/auth/google/link",
            headers={"Authorization": f"Bearer {access_token}"},
            json={"id_token": valid_token},
        )
        assert link_res.status_code == 200
        linked_user = link_res.json()
        assert linked_user["email"] == email
        assert linked_user["is_google_linked"] is True
        assert linked_user["has_password"] is True

        # Duplicate link attempt on an already-linked account -> 400
        dup_link_res = await client.post(
            "/api/v1/auth/google/link",
            headers={"Authorization": f"Bearer {access_token}"},
            json={"id_token": valid_token},
        )
        assert dup_link_res.status_code == 400
        assert "đã được liên kết" in dup_link_res.json()["detail"]

        # Subsequent Google login succeeds directly without requiring a password -> 200 OK
        google_login_res = await client.post(
            "/api/v1/auth/google",
            json={"id_token": valid_token},
        )
        assert google_login_res.status_code == 200
        assert google_login_res.json()["user"]["is_google_linked"] is True


# ==============================================================================
# 3. PASSWORD-VERIFIED LINKING FOR EXISTING UNLINKED EMAIL ACCOUNTS
# ==============================================================================


@pytest.mark.asyncio
async def test_google_login_existing_email_requires_password_verification(mock_google_certs):
    """Requires password verification before linking when Google login matches an unlinked email account."""
    transport = ASGITransport(app=app)
    uid = uuid.uuid4().hex[:6]
    shared_email = f"shared_{uid}@gmail.com"
    username = f"shared_user_{uid}"
    password = "ManualPassword123!"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        reg_data = await _register_verified_email_user(
            client,
            email=shared_email,
            username=username,
            password=password,
        )
        assert reg_data["user"]["is_google_linked"] is False

        valid_google_token = create_signed_google_id_token(
            sub=f"google_sub_{shared_email}",
            email=shared_email,
            name="Google Name",
            picture="https://avatar.google/photo.jpg",
        )

        # Omitting password returns 409 Conflict prompting password confirmation
        res_no_pwd = await client.post(
            "/api/v1/auth/google",
            json={"id_token": valid_google_token},
        )
        assert res_no_pwd.status_code == 409
        assert "nhập mật khẩu" in res_no_pwd.json()["detail"]

        # Incorrect password returns 401 Unauthorized
        res_wrong_pwd = await client.post(
            "/api/v1/auth/google",
            json={
                "id_token": valid_google_token,
                "password": "WrongPassword999!",
            },
        )
        assert res_wrong_pwd.status_code == 401
        assert "không chính xác" in res_wrong_pwd.json()["detail"]

        # Correct password links the Google identity and logs the user in -> 200 OK
        res_correct_pwd = await client.post(
            "/api/v1/auth/google",
            json={
                "id_token": valid_google_token,
                "password": password,
                "platform": "MOBILE",
                "device_id": "pixel_8_pro",
            },
        )
        assert res_correct_pwd.status_code == 200
        google_data = res_correct_pwd.json()
        assert google_data["success"] is True
        assert google_data["require_password_setup"] is False
        assert google_data["user"]["email"] == shared_email
        assert google_data["user"]["username"] == username
        assert google_data["user"]["is_google_linked"] is True
        assert google_data["user"]["has_password"] is True

        # Subsequent Google logins succeed without requiring the password again -> 200 OK
        res_subsequent = await client.post(
            "/api/v1/auth/google",
            json={"id_token": valid_google_token},
        )
        assert res_subsequent.status_code == 200


# ==============================================================================
# 4. AUTOMATIC USER PROVISIONING & PASSWORD SETUP FOR NEW GOOGLE ACCOUNTS
# ==============================================================================


@pytest.mark.asyncio
async def test_google_login_provisions_new_user_and_prompts_password_setup(mock_google_certs):
    """Provisions a new account for first-time Google users and sets require_password_setup until a password is set."""
    transport = ASGITransport(app=app)
    google_email = f"new_oauth_{uuid.uuid4().hex[:6]}@gmail.com"
    valid_google_token = create_signed_google_id_token(
        sub=f"google_sub_{google_email}",
        email=google_email,
        name="Pure Google Fan",
    )

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # First login provisions the account with has_password=False and require_password_setup=True
        google_res_1 = await client.post(
            "/api/v1/auth/google",
            json={"id_token": valid_google_token},
        )
        assert google_res_1.status_code == 200
        data_1 = google_res_1.json()
        assert data_1["user"]["has_password"] is False
        assert data_1["require_password_setup"] is True

        # Subsequent Google login before setting a password still returns require_password_setup=True
        google_res_2 = await client.post(
            "/api/v1/auth/google",
            json={"id_token": valid_google_token},
        )
        assert google_res_2.status_code == 200
        data_2 = google_res_2.json()
        assert data_2["user"]["has_password"] is False
        assert data_2["require_password_setup"] is True
        token = data_2["tokens"]["access_token"]

        # Request OTP and establish a password via /api/v1/auth/password/oauth-set
        otp_res = await client.post(
            "/api/v1/auth/email/send-otp",
            json={"email": google_email, "purpose": "OAUTH_SET_PASSWORD"},
        )
        assert otp_res.status_code == 200
        otp_code = otp_res.json()["dev_otp"]

        set_res = await client.post(
            "/api/v1/auth/password/oauth-set",
            headers={"Authorization": f"Bearer {token}"},
            json={"otp_code": otp_code, "new_password": "NewCreatedPassword123!"},
        )
        assert set_res.status_code == 200
        assert set_res.json()["success"] is True

        # Google login after password setup returns has_password=True and require_password_setup=False
        google_res_3 = await client.post(
            "/api/v1/auth/google",
            json={"id_token": valid_google_token},
        )
        assert google_res_3.status_code == 200
        data_3 = google_res_3.json()
        assert data_3["user"]["has_password"] is True
        assert data_3["require_password_setup"] is False

        # Standard Email/Password login also succeeds with the newly configured password
        login_res = await client.post(
            "/api/v1/auth/login",
            json={"email": google_email, "password": "NewCreatedPassword123!"},
        )
        assert login_res.status_code == 200
        assert login_res.json()["success"] is True


# ==============================================================================
# 5. PASSWORD LOGIN REJECTION FOR OAUTH-ONLY ACCOUNTS
# ==============================================================================


@pytest.mark.asyncio
async def test_password_login_rejected_for_oauth_only_account(mock_google_certs):
    """Rejects standard Email/Password login with 400 Bad Request when an OAuth-created account has no password set."""
    transport = ASGITransport(app=app)
    google_email = f"oauth_nopwd_{uuid.uuid4().hex[:6]}@gmail.com"
    valid_google_token = create_signed_google_id_token(
        sub=f"google_sub_{google_email}",
        email=google_email,
        name="OAuth Only User",
    )

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        google_res = await client.post(
            "/api/v1/auth/google",
            json={"id_token": valid_google_token},
        )
        assert google_res.status_code == 200
        assert google_res.json()["user"]["has_password"] is False

        login_res = await client.post(
            "/api/v1/auth/login",
            json={"email": google_email, "password": "RandomAttemptPassword123!"},
        )
        assert login_res.status_code == 400
        detail = login_res.json()["detail"]
        assert "tạo qua Google" in detail and "chưa thiết lập mật khẩu" in detail

