"""Unit & Integration Tests for Staged User Registration & OTP Verification (FR-01).

Covers:
1. Valid 2-step registration cases:
   - Step 1 (`POST /api/v1/auth/register`): Stages registration in Redis (10m TTL) and dispatches OTP email via SMTP.
     Verifies NO User record exists in PostgreSQL before OTP verification.
   - Step 2 (`POST /api/v1/auth/email/verify-otp`): Verifies 6-digit OTP, creates User (`is_email_verified=True`),
     Wallet (`coin_balance=0`), and Session in PostgreSQL, and returns JWT tokens.
   - Minimal required fields & full fields with `platform="MOBILE"` and `device_id`.
2. Missing required fields (`email`, `username`, `password`, `display_name`, empty body, MOBILE without `device_id`).
3. Invalid field formats & business constraints (malformed email, username length/regex, password length,
   display_name length, duplicate email, duplicate username, reserved username in Redis & auto-release).
4. Expiration, Anti-Brute-Force & Anti-Spam protections:
   - Auto-cancellation when 10-minute staged registration TTL expires.
   - Immediate cancellation of both OTP and staged registration after 5 wrong OTP attempts.
   - Rejection of unrequested `/api/v1/auth/email/send-otp` calls for arbitrary emails.
   - IP registration rate limit (max 5 per 10 minutes).
5. Outgoing SMTP Email verification (both payload inspection and live Gmail SMTP TLS authentication check).
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
# 1. CASE ĐỦ TRƯỜNG HỢP LỆ & KIỂM CHỨNG CHƯA TẠO USER TRƯỚC KHI XÁC THỰC OTP
# ==============================================================================


@pytest.mark.asyncio
async def test_register_staged_and_verified_minimal_fields(mock_smtp_send):
    """Kiểm tra luồng chuẩn 2 bước: Gửi form đăng ký (chưa tạo User DB, có gửi mail OTP) -> Xác thực OTP mới tạo User."""
    transport = ASGITransport(app=app)
    uid = uuid.uuid4().hex[:8]
    email = f"valid_min_{uid}@example.com"
    username = f"user_min_{uid}"
    password = "ValidPassword123!"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Bước 1: Gửi yêu cầu đăng ký -> Lưu tạm trên Redis & gửi OTP
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
        assert "tokens" not in reg_data  # Chưa cấp token!
        otp_code = reg_data["dev_otp"]
        assert otp_code and len(otp_code) == 6

        # Kiểm chứng: Hàm gửi email SMTP đã được gọi với đúng người nhận và chứa mã OTP 6 số
        assert mock_smtp_send.called
        sent_msg = mock_smtp_send.call_args[0][0]
        assert sent_msg["To"] == email
        assert otp_code in sent_msg["Subject"]

        # Kiểm chứng: Khi chưa xác thực OTP, tài khoản CHƯA tồn tại trong PostgreSQL (đăng nhập trả về 401)
        premature_login = await client.post(
            "/api/v1/auth/login",
            json={"email": email, "password": password},
        )
        assert premature_login.status_code == 401

        # Bước 2: Xác thực mã OTP -> Lúc này mới chính thức tạo User trong PostgreSQL và cấp JWT Token
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

        # Kiểm chứng: Key đăng ký tạm trên Redis đã được dọn sạch sau khi tạo tài khoản
        r = get_redis_client()
        assert await r.get(f"pending_reg:email:{email}") is None
        assert await r.get(f"pending_reg:username:{username.lower()}") is None


@pytest.mark.asyncio
async def test_register_staged_and_verified_full_mobile_fields():
    """Đăng ký thành công khi truyền đầy đủ cả trường bắt buộc lẫn tùy chọn (platform='MOBILE' + device_id)."""
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
# 2. CASE THIẾU TRƯỜNG (MISSING FIELDS)
# ==============================================================================


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "missing_field",
    ["email", "username", "password", "display_name"],
)
async def test_register_missing_each_required_field(missing_field: str):
    """Bỏ trống từng trường bắt buộc (email, username, password, display_name) phải bị từ chối với 422."""
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
    """Gửi body rỗng {} khi đăng ký phải bị từ chối với 422."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        res = await client.post("/api/v1/auth/register", json={})
        assert res.status_code == 422
        assert len(res.json()["detail"]) >= 4


@pytest.mark.asyncio
async def test_register_mobile_missing_device_id():
    """Đăng ký trên nền tảng MOBILE nhưng thiếu device_id phải bị từ chối với 400."""
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
# 3. CASE SAI TRƯỜNG / SAI ĐỊNH DẠNG / TRÙNG LẶP / GIỮ CHỖ USERNAME
# ==============================================================================


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "invalid_payload_override,expected_field",
    [
        ({"email": "not-an-email"}, "email"),
        ({"email": "@missing-local.com"}, "email"),
        ({"email": ""}, "email"),
        ({"username": "ab"}, "username"),  # < 3 chars
        ({"username": "a" * 51}, "username"),  # > 50 chars
        ({"username": "bad space"}, "username"),  # contains whitespace
        ({"username": "bad@char!"}, "username"),  # contains special chars outside [a-zA-Z0-9_-]
        ({"password": "12345"}, "password"),  # < 6 chars
        ({"password": "p" * 101}, "password"),  # > 100 chars
        ({"display_name": ""}, "display_name"),  # < 1 char
        ({"display_name": "d" * 101}, "display_name"),  # > 100 chars
    ],
)
async def test_register_invalid_field_formats(invalid_payload_override: dict, expected_field: str):
    """Kiểm tra toàn bộ ràng buộc định dạng (email, độ dài/regex username, độ dài password, display_name)."""
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
    """Đăng ký trùng email hoặc trùng username đã tạo trong DB phải bị từ chối với 400."""
    transport = ASGITransport(app=app)
    uid = uuid.uuid4().hex[:6]
    email = f"dup_{uid}@example.com"
    username = f"dup_user_{uid}"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Tạo tài khoản gốc và hoàn tất OTP
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

        # 2. Trùng email nhưng khác username -> 400
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

        # 3. Trùng username nhưng khác email -> 400
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
    """Khi User A đang giữ chỗ username chờ OTP, User B không thể lấy; nhưng khi yêu cầu của A tự hủy, B lấy được."""
    transport = ASGITransport(app=app)
    uid = uuid.uuid4().hex[:6]
    hot_username = f"idol_{uid}"
    email_a = f"user_a_{uid}@example.com"
    email_b = f"user_b_{uid}@example.com"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. User A đăng ký giữ chỗ hot_username (chưa nhập OTP)
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

        # 2. User B cố lấy cùng hot_username khi yêu cầu của A vẫn còn hạn -> 400
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

        # 3. Giả lập yêu cầu của User A hết hạn tự hủy sau 10 phút trên Redis
        r = get_redis_client()
        await r.delete(f"pending_reg:email:{email_a}")
        await r.delete(f"pending_reg:username:{hot_username.lower()}")

        # 4. Giờ User B đăng ký lại hot_username -> Thành công (202 Accepted)
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
# 4. TỰ HỦY KHI QUÁ HẠN, HỦY KHI SAI OTP 5 LẦN & CHỐNG SPAM OTP
# ==============================================================================


@pytest.mark.asyncio
async def test_register_auto_cancel_after_ttl_expiration():
    """Nếu yêu cầu đăng ký tạm hết hạn 10 phút trên Redis, gọi verify-otp phải báo lỗi 400 và không tạo User."""
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

        # Giả lập hết hạn TTL 10 phút của pending_reg
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
    """Nhập sai OTP 5 lần liên tiếp sẽ tự hủy cả mã OTP lẫn yêu cầu đăng ký tạm trên Redis."""
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

        # Nhập sai 5 lần liên tiếp
        for i in range(5):
            bad_res = await client.post(
                "/api/v1/auth/email/verify-otp",
                json={"email": email, "code": "000000", "purpose": "VERIFY_EMAIL"},
            )
            assert bad_res.status_code == 400

        # Kiểm chứng: Yêu cầu đăng ký tạm đã bị xóa khỏi Redis sau lần sai thứ 5
        r = get_redis_client()
        assert await r.get(f"pending_reg:email:{email}") is None

        # Ngay cả khi nhập đúng mã OTP thật ở lần thứ 6 -> Vẫn bị từ chối vì yêu cầu đã bị hủy
        late_res = await client.post(
            "/api/v1/auth/email/verify-otp",
            json={"email": email, "code": real_otp, "purpose": "VERIFY_EMAIL"},
        )
        assert late_res.status_code == 400


@pytest.mark.asyncio
async def test_send_otp_rejects_unrequested_random_email():
    """Chống spam OTP: Gọi /email/send-otp cho một email lạ chưa từng gửi form đăng ký phải bị chặn với 400."""
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
    """Giới hạn tối đa 5 lượt khởi tạo đăng ký trên mỗi địa chỉ IP trong 10 phút; lượt thứ 6 trả về 429."""
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

        # Lượt thứ 6 từ cùng IP -> 429 Too Many Requests
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
# 5. KIỂM TRA KẾT NỐI VÀ XÁC THỰC GMAIL SMTP THẬT (LIVE SMTP AUTHENTICATION CHECK)
# ==============================================================================


@pytest.mark.asyncio
async def test_gmail_smtp_live_authentication():
    """Kiểm tra trực tiếp kết nối TLS và đăng nhập vào máy chủ smtp.gmail.com:587 bằng cấu hình .env."""
    if not settings.SMTP_USER or not settings.SMTP_PASSWORD:
        pytest.skip("Chưa cấu hình SMTP_USER / SMTP_PASSWORD trong .env")

    smtp = aiosmtplib.SMTP(
        hostname=settings.SMTP_HOST,
        port=settings.SMTP_PORT,
        start_tls=True,
        timeout=10.0,
    )
    await smtp.connect()
    auth_response = await smtp.login(settings.SMTP_USER, settings.SMTP_PASSWORD)
    await smtp.quit()
    assert auth_response.code == 235  # 235 2.7.0 Accepted
