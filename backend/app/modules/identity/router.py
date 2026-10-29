"""Identity and Authentication API Router.

This module exposes RESTful endpoints for user registration, multi-platform login,
Google OAuth2 integration, Redis-backed OTP email verification, token refresh rotation,
device session management, and account soft deletion.
"""

import urllib.parse
import uuid
import httpx
import orjson
from fastapi import APIRouter, Depends, status, Request, BackgroundTasks, HTTPException
from fastapi.responses import RedirectResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
import redis.asyncio as aioredis

from app.core.config import get_settings
from app.core.database import get_db
from app.core.redis import get_redis
from app.core.client_detector import extract_client_info
from app.modules.identity.models import User
from app.modules.identity.schemas import (
    UserRegister,
    UserLogin,
    GoogleLogin,
    GoogleLinkRequest,
    Token,
    UserOut,
    RefreshTokenRequest,
    OAuthTicketExchangeRequest,
    EmailSendOTPRequest,
    EmailVerifyOTPRequest,
    OAuthSetPasswordRequest,
    DeleteAccountRequest,
    SessionOut,
    AuthResponse,
    RegisterInitResponse,
    OTPVerifyResponse,
    MessageResponse,
    OTPSendResponse,
    GoogleAuthUrlResponse,
    RevokeAllSessionsResponse,
    UserUpdateProfile,
    PasswordChangeRequest,
)
from app.core.security import get_password_hash, verify_password
from app.modules.identity.service import (
    IdentityService,
    get_current_user,
    get_current_user_and_session,
)
from app.modules.identity.otp_service import OTPService, OTPPurpose

settings = get_settings()
auth_router = APIRouter(prefix="/api/v1/auth", tags=["Authentication & Identity"])
users_router = APIRouter(prefix="/api/v1/users", tags=["Users"])


def to_user_out(user: User) -> UserOut:
    """Serializes a SQLAlchemy User model into a validated UserOut schema.

    Args:
        user (User): The database user entity.

    Returns:
        UserOut: Clean, public-facing user profile schema.
    """
    return UserOut(
        id=user.id,
        email=user.email,
        username=user.username,
        display_name=user.display_name,
        avatar_url=user.avatar_url,
        bio=user.bio,
        coin_balance=user.wallet.coin_balance if user.wallet else 0,
        is_email_verified=user.is_email_verified,
        system_role=user.system_role,
        has_password=bool(user.password_hash),
        is_google_linked=bool(user.google_id),
        created_at=user.created_at,
    )


@auth_router.post(
    "/register",
    response_model=RegisterInitResponse,
    status_code=status.HTTP_202_ACCEPTED,
    summary="Khởi tạo yêu cầu đăng ký tài khoản (lưu tạm Redis & gửi OTP)",
    description="""
    Ghi nhận yêu cầu đăng ký tạm thời trên Redis và gửi mã OTP 6 số về Email:
    - **Chưa tạo tài khoản trong DB**: Bảo vệ cơ sở dữ liệu khỏi tài khoản rác chưa xác thực email.
    - **Tự động hủy sau 10 phút**: Yêu cầu đăng ký tạm (`pending_reg`) tự hủy nếu không xác thực OTP trong 10 phút.
    - **Kiểm tra trùng lặp & giữ chỗ**: Xác thực Email và Username chưa tồn tại trong DB và chưa bị giữ chỗ.
    - **Rate Limit**: Giới hạn tối đa 5 lượt đăng ký trên mỗi địa chỉ IP trong vòng 10 phút.
    """,
    responses={
        400: {"description": "Email hoặc Username đã tồn tại/đang được giữ chỗ, hoặc thiếu Device ID cho Mobile"},
        429: {"description": "Địa chỉ IP đã vượt quá giới hạn đăng ký hoặc đang trong thời gian chờ OTP cooldown"},
    },
)
async def register(
    data: UserRegister,
    request: Request,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    """Stages user registration in Redis (10m TTL) and dispatches OTP verification email."""
    client_info = extract_client_info(request, data.platform, data.device_id)
    otp_code = await IdentityService.register(db, data, client_info, redis, background_tasks)
    clean_email = str(data.email).strip().lower()
    return RegisterInitResponse(
        success=True,
        require_otp=True,
        email=clean_email,
        expires_in_seconds=settings.PENDING_REGISTRATION_TTL_SECONDS,
        message=f"Mã OTP xác thực đã được gửi tới {clean_email}. Vui lòng xác thực trong vòng 5 phút để tạo tài khoản (yêu cầu tự hủy sau 10 phút).",
        dev_otp=otp_code if (settings.DEBUG and settings.DEBUG_OTP_IN_RESPONSE) else None,
    )



@auth_router.post(
    "/login",
    response_model=AuthResponse,
    summary="Đăng nhập bằng Email và Mật khẩu",
    description="""
    Xác thực người dùng bằng thông tin đăng nhập:
    - **Xác thực Argon2id**: Kiểm tra mật khẩu khớp với hash đã lưu.
    - **Chống Brute-force**: Tự động khóa đăng nhập 15 phút nếu nhập sai mật khẩu 5 lần liên tiếp.
    - **Quy tắc 1 phiên/nền tảng**: Cấp phiên mới và đăng xuất thiết bị cũ trên cùng nền tảng.
    """,
    responses={
        401: {"description": "Email hoặc mật khẩu không chính xác"},
        429: {"description": "Tài khoản tạm thời bị khóa do nhập sai mật khẩu quá 5 lần"},
    },
)
async def login(
    data: UserLogin,
    request: Request,
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    """Authenticates credentials and establishes a new platform session."""
    client_info = extract_client_info(request, data.platform, data.device_id)
    user, tokens = await IdentityService.login(db, data, client_info, redis)
    return AuthResponse(
        success=True,
        message="Đăng nhập thành công.",
        tokens=tokens,
        user=to_user_out(user),
    )


@auth_router.post(
    "/google",
    response_model=AuthResponse,
    summary="Đăng nhập qua Google OAuth2 (ID Token)",
    description="""
    Xác thực người dùng hoặc khởi tạo tài khoản mới thông qua Google ID Token:
    - **Xác thực chữ ký số**: Kiểm tra tính hợp lệ của token với máy chủ Google và Client ID cấu hình.
    - **Liên kết tài khoản trùng email**: Nếu email Google trùng với tài khoản Email/Mật khẩu hiện có chưa liên kết Google, yêu cầu xác minh `password` trước khi liên kết (trả về `409 Conflict` nếu chưa cung cấp mật khẩu).
    - **Khởi tạo tài khoản mới**: Nếu email chưa tồn tại trên hệ thống, tự động khởi tạo tài khoản với `has_password = False` và trả về cờ `require_password_setup = True`.
    """,
    responses={
        400: {"description": "Thiếu thông tin thiết bị hoặc tài khoản đã liên kết với định danh Google khác"},
        401: {"description": "Google ID token không hợp lệ hoặc mật khẩu xác nhận liên kết không chính xác"},
        409: {"description": "Email đã tồn tại nhưng chưa liên kết Google — yêu cầu xác nhận mật khẩu tài khoản hiện có"},
    },
)
async def google_login(
    data: GoogleLogin,
    request: Request,
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    """Processes Google OAuth authentication, password-verified account linking, and automatic user provisioning."""
    client_info = extract_client_info(request, data.platform, data.device_id)
    user, tokens = await IdentityService.google_login(db, data, client_info, redis)
    user_out = to_user_out(user)
    return AuthResponse(
        success=True,
        message="Đăng nhập qua Google thành công.",
        require_password_setup=not user_out.has_password,
        tokens=tokens,
        user=user_out,
    )


@auth_router.post(
    "/google/link",
    response_model=UserOut,
    summary="Liên kết tài khoản hiện tại với Google",
    description="""
    Liên kết tài khoản đang đăng nhập với định danh Google OAuth2:
    - **Xác thực Google ID Token**: Kiểm tra chữ ký số RSA và trạng thái `email_verified` với Google.
    - **Kiểm tra trùng khớp**: Email trên tài khoản Google phải trùng khớp với email của tài khoản hiện tại và chưa được liên kết với tài khoản khác.
    """,
    responses={
        400: {"description": "Tài khoản đã liên kết Google hoặc email Google không trùng khớp"},
        401: {"description": "Chưa xác thực phiên đăng nhập hoặc Google ID token không hợp lệ"},
    },
)
async def link_google_account(
    data: GoogleLinkRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Links a verified Google account to the currently authenticated user profile."""
    updated_user = await IdentityService.link_google_account(db, current_user, data)
    return to_user_out(updated_user)


@auth_router.get(
    "/google/login",
    summary="Khởi tạo cổng ủy quyền Google OAuth2",
    description="Chuyển hướng trình duyệt tới Google Consent Screen (307 Redirect) hoặc trả về JSON URL.",
)
async def google_login_url(request: Request):
    """Generates the Google OAuth2 consent screen authorization URL and redirects."""
    if not settings.GOOGLE_CLIENT_ID:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="GOOGLE_CLIENT_ID chưa được cấu hình.",
        )
    params = {
        "client_id": settings.GOOGLE_CLIENT_ID,
        "redirect_uri": settings.GOOGLE_REDIRECT_URI,
        "response_type": "code",
        "scope": "openid email profile",
        "access_type": "offline",
        "prompt": "select_account",
    }
    auth_url = f"https://accounts.google.com/o/oauth2/v2/auth?{urllib.parse.urlencode(params)}"

    accept = request.headers.get("accept", "")
    if "application/json" in accept and "text/html" not in accept:
        return GoogleAuthUrlResponse(url=auth_url)

    return RedirectResponse(url=auth_url, status_code=status.HTTP_307_TEMPORARY_REDIRECT)


@auth_router.get(
    "/google/callback",
    response_model=AuthResponse,
    summary="Callback xử lý mã ủy quyền Google OAuth2",
    description="Nhận Authorization Code từ Google, trao đổi lấy token, tìm/tạo tài khoản và cấp JWT.",
)
async def google_oauth_callback(
    code: str,
    request: Request,
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    """Exchanges an authorization code with Google for tokens and logs the user in."""
    accept = request.headers.get("accept", "")
    is_browser = "text/html" in accept

    token_url = "https://oauth2.googleapis.com/token"
    async with httpx.AsyncClient() as client:
        res = await client.post(
            token_url,
            data={
                "code": code,
                "client_id": settings.GOOGLE_CLIENT_ID,
                "client_secret": settings.GOOGLE_CLIENT_SECRET,
                "redirect_uri": settings.GOOGLE_REDIRECT_URI,
                "grant_type": "authorization_code",
            },
        )
        if res.status_code != 200:
            error_detail = f"Lỗi trao đổi mã ủy quyền với Google: {res.text}"
            if is_browser:
                return RedirectResponse(
                    url=f"http://localhost:3000/auth/callback?error={urllib.parse.quote(error_detail)}"
                )
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=error_detail,
            )
        token_data = res.json()
        id_token_val = token_data.get("id_token")
        if not id_token_val:
            error_detail = "Phản hồi từ Google không chứa id_token hợp lệ."
            if is_browser:
                return RedirectResponse(
                    url=f"http://localhost:3000/auth/callback?error={urllib.parse.quote(error_detail)}"
                )
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=error_detail,
            )

    client_info = extract_client_info(request)
    try:
        user, tokens = await IdentityService.google_login(
            db, GoogleLogin(id_token=id_token_val), client_info, redis
        )
    except HTTPException as exc:
        if is_browser:
            return RedirectResponse(
                url=f"http://localhost:3000/auth/callback?error={urllib.parse.quote(str(exc.detail))}"
            )
        raise exc

    user_out = to_user_out(user)
    if is_browser:
        # Secure OAuth2 One-Time Exchange Ticket (TTL 60s in Redis)
        ticket = str(uuid.uuid4())
        ticket_data = {
            "tokens": tokens.model_dump(mode="json"),
            "user": user_out.model_dump(mode="json"),
        }
        await redis.setex(f"oauth_ticket:{ticket}", 60, orjson.dumps(ticket_data).decode("utf-8"))
        redirect_url = f"http://localhost:3000/auth/callback?ticket={ticket}"
        return RedirectResponse(url=redirect_url)

    return AuthResponse(
        success=True,
        message="Xác thực Google OAuth2 thành công.",
        require_password_setup=not user_out.has_password,
        tokens=tokens,
        user=user_out,
    )


@auth_router.post(
    "/exchange-ticket",
    response_model=AuthResponse,
    summary="Đổi mã vé OAuth tạm thời (Ticket) lấy JWT Tokens",
    description="""
    Đổi mã vé dùng 1 lần (Single-use ticket) nhận được từ OAuth Callback lấy cặp JWT access và refresh tokens:
    - **Bảo mật**: Mã vé được lưu trong Redis với TTL 60 giây và bị xóa ngay lập tức sau khi đổi (Zero token in URL).
    """,
    responses={
        400: {"description": "Mã vé không hợp lệ hoặc đã hết hạn (quá 60 giây)"},
    },
)
async def exchange_oauth_ticket(
    data: OAuthTicketExchangeRequest,
    redis: aioredis.Redis = Depends(get_redis),
):
    """Validates and exchanges a single-use OAuth ticket for user session tokens."""
    ticket_key = f"oauth_ticket:{data.ticket}"
    raw_data = await redis.get(ticket_key)
    if not raw_data:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Mã vé xác thực không hợp lệ hoặc đã hết hạn. Vui lòng đăng nhập lại.",
        )
    # Immediately delete to enforce single-use protection
    await redis.delete(ticket_key)

    payload = orjson.loads(raw_data)
    user_out = UserOut(**payload["user"])
    return AuthResponse(
        success=True,
        message="Đăng nhập Google thành công.",
        require_password_setup=not user_out.has_password,
        tokens=Token(**payload["tokens"]),
        user=user_out,
    )



@auth_router.post(
    "/email/send-otp",
    response_model=OTPSendResponse,
    summary="Gửi mã xác thực OTP qua Email",
    description="""
    Sinh mã OTP ngẫu nhiên 6 số và gửi tới email của người dùng:
    - **Chống spam email lạ**: Với `VERIFY_EMAIL`, bắt buộc phải có yêu cầu đăng ký tạm (`pending_reg`) đang tồn tại trên Redis. Với các mục đích khác, email phải thuộc về tài khoản đang hoạt động.
    - **Lưu trữ Redis**: TTL 5 phút (300 giây).
    - **Chống spam tần suất**: Cooldown 60 giây giữa các lần yêu cầu, tối đa 5 mã/giờ.
    """,
    responses={
        400: {"description": "Không tìm thấy yêu cầu đăng ký hợp lệ hoặc tài khoản không tồn tại"},
        429: {"description": "Đang trong thời gian chờ cooldown 60s hoặc đã vượt quá 5 mã/giờ"},
    },
)
async def send_email_otp(
    data: EmailSendOTPRequest,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    """Generates and sends an OTP code via email in background after verifying request legitimacy."""
    clean_email = str(data.email).strip().lower()

    if data.purpose == OTPPurpose.VERIFY_EMAIL:
        pending_key = f"pending_reg:email:{clean_email}"
        raw_pending = await redis.get(pending_key)
        if not raw_pending:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Không tìm thấy yêu cầu đăng ký đang chờ xác thực cho email này (hoặc đã tự hủy sau 10 phút). Vui lòng đăng ký lại.",
            )
        # Refresh 10-minute TTL on pending registration when user legitimately requests OTP resend
        await redis.expire(pending_key, settings.PENDING_REGISTRATION_TTL_SECONDS)
        try:
            staged = orjson.loads(raw_pending)
            uname = staged.get("username", "").lower()
            if uname:
                await redis.expire(
                    f"pending_reg:username:{uname}",
                    settings.PENDING_REGISTRATION_TTL_SECONDS,
                )
        except Exception:
            pass
    else:
        query = select(User).where(User.email == clean_email, User.is_active == True)
        result = await db.execute(query)
        if not result.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Không tìm thấy tài khoản hoạt động tương ứng với địa chỉ email này.",
            )

    code = await OTPService.send_otp(redis, clean_email, data.purpose, background_tasks)
    return OTPSendResponse(
        success=True,
        message=f"Mã OTP xác thực đã được gửi tới {clean_email}. Hiệu lực trong 5 phút.",
        dev_otp=code if (settings.DEBUG and settings.DEBUG_OTP_IN_RESPONSE) else None,
    )


@auth_router.post(
    "/email/verify-otp",
    response_model=OTPVerifyResponse,
    summary="Xác thực mã OTP và chính thức khởi tạo tài khoản",
    description="""
    Xác nhận mã OTP 6 số người dùng nhập:
    - **Single-use**: Mã bị hủy ngay sau khi xác thực thành công.
    - **Chống Brute-force**: Hủy cả mã OTP lẫn yêu cầu đăng ký tạm nếu nhập sai quá 5 lần liên tiếp.
    - **Khởi tạo tài khoản (`VERIFY_EMAIL`)**: Chính thức tạo `User` (`is_email_verified = True`), `Wallet` (0 xu), `UserSession` trong PostgreSQL và trả về cặp JWT `tokens` + `user`.
    """,
    responses={
        400: {"description": "Yêu cầu đăng ký đã tự hủy, hoặc mã OTP không tồn tại, hết hạn, nhập sai"},
    },
)
async def verify_email_otp(
    data: EmailVerifyOTPRequest,
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    """Verifies an OTP and provisions the user account in PostgreSQL when purpose is VERIFY_EMAIL."""
    if data.purpose == OTPPurpose.VERIFY_EMAIL:
        user, tokens = await IdentityService.complete_registration(
            db, redis, str(data.email), data.code
        )
        return OTPVerifyResponse(
            success=True,
            message="Xác thực mã OTP thành công. Tài khoản đã được tạo và kích hoạt.",
            tokens=tokens,
            user=to_user_out(user),
        )

    await OTPService.verify_otp(redis, str(data.email), data.code, data.purpose)
    return OTPVerifyResponse(
        success=True,
        message="Xác thực mã OTP thành công.",
    )



@auth_router.post(
    "/password/oauth-set",
    response_model=MessageResponse,
    summary="Thiết lập mật khẩu cho tài khoản Google OAuth",
    description="""
    Cho phép tài khoản đăng ký ban đầu qua Google tạo mật khẩu cá nhân:
    - **Xác thực danh tính**: Bắt buộc cung cấp mã OTP gửi về email Google của tài khoản.
    - **Kết quả**: Sau khi thiết lập mật khẩu, người dùng có thể đăng nhập bằng cả Google lẫn Email/Mật khẩu.
    """,
    responses={
        400: {"description": "Mã OTP không chính xác hoặc đã hết hạn"},
        401: {"description": "Chưa đăng nhập hoặc phiên đăng nhập không hợp lệ"},
    },
)
async def oauth_set_password(
    data: OAuthSetPasswordRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    """Sets a password on an OAuth-created account after OTP verification."""
    result = await IdentityService.oauth_set_password(db, current_user, data, redis)
    return MessageResponse(success=True, message=result["message"])


@auth_router.post(
    "/refresh",
    response_model=Token,
    summary="Cấp mới Access Token (Refresh Token Rotation)",
    description="""
    Sử dụng Refresh Token để lấy Access Token mới:
    - **Token Rotation**: Cấp Refresh Token mới và thu hồi Refresh Token cũ.
    - **Chống giả mạo**: Phát hiện và vô hiệu hóa ngay lập tức phiên làm việc nếu Refresh Token bị dùng lại.
    """,
    responses={
        401: {"description": "Refresh token không hợp lệ, đã hết hạn, hoặc bị tái sử dụng trái phép"},
    },
)
async def refresh_access_token(
    data: RefreshTokenRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    """Rotates refresh tokens and issues fresh access tokens."""
    client_info = extract_client_info(request)
    return await IdentityService.refresh_token(db, data.refresh_token, client_info)


@auth_router.get(
    "/sessions",
    response_model=list[SessionOut],
    summary="Xem danh sách các phiên đăng nhập đang hoạt động",
    description="Trả về danh sách các thiết bị/phiên đang đăng nhập của tài khoản kèm IP, tên thiết bị và thời điểm hoạt động.",
    responses={
        401: {"description": "Phiên đăng nhập không hợp lệ hoặc đã bị đăng xuất"},
    },
)
async def list_active_sessions(
    auth_data: tuple[User, uuid.UUID | None] = Depends(get_current_user_and_session),
    db: AsyncSession = Depends(get_db),
):
    """Lists all active device sessions for the authenticated user."""
    user, current_session_id = auth_data
    return await IdentityService.list_sessions(db, user.id, current_session_id)


@auth_router.post(
    "/sessions/{session_id}/revoke",
    response_model=MessageResponse,
    summary="Đăng xuất từ xa khỏi một thiết bị cụ thể",
    description="Thu hồi phiên làm việc trên một thiết bị đã chọn, buộc thiết bị đó phải đăng nhập lại.",
    responses={
        404: {"description": "Không tìm thấy phiên đăng nhập hoặc phiên không thuộc về bạn"},
    },
)
async def revoke_session(
    session_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Revokes a specific session owned by the authenticated user."""
    success = await IdentityService.revoke_session(db, current_user.id, session_id)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Không tìm thấy phiên đăng nhập hoặc bạn không có quyền.",
        )
    return MessageResponse(success=True, message="Thu hồi phiên đăng nhập thành công.")


@auth_router.post(
    "/sessions/revoke-all",
    response_model=RevokeAllSessionsResponse,
    summary="Đăng xuất khỏi tất cả các thiết bị khác",
    description="Hủy toàn bộ các phiên làm việc trên các thiết bị khác ngoại trừ thiết bị đang thực hiện yêu cầu.",
    responses={
        400: {"description": "Không thể xác định phiên đăng nhập hiện tại"},
    },
)
async def revoke_all_other_sessions(
    auth_data: tuple[User, uuid.UUID | None] = Depends(get_current_user_and_session),
    db: AsyncSession = Depends(get_db),
):
    """Revokes all sessions for the user except the active one."""
    user, current_session_id = auth_data
    if not current_session_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Không thể xác định phiên đăng nhập hiện tại.",
        )
    revoked_count = await IdentityService.revoke_all_other_sessions(db, user.id, current_session_id)
    return RevokeAllSessionsResponse(
        success=True,
        message=f"Đã đăng xuất khỏi {revoked_count} thiết bị khác thành công.",
        revoked_count=revoked_count,
    )


from app.modules.media.service import MediaService


@auth_router.post(
    "/delete-account",
    response_model=MessageResponse,
    summary="Yêu cầu xóa tài khoản người dùng",
    description="""
    Thực hiện xóa mềm (Soft-delete) tài khoản người dùng:
    - **Xác thực bảo mật**: Yêu cầu nhập mật khẩu hiện tại (hoặc mã OTP nếu tài khoản thuần mạng xã hội).
    - **Thu hồi phiên**: Hủy ngay lập tức mọi phiên đăng nhập trên mọi nền tảng thiết bị.
    - **Khóa tài khoản**: Đánh dấu `is_active = False` và lưu thời điểm xóa.
    """,
    responses={
        400: {"description": "Mật khẩu xác nhận hoặc mã OTP không chính xác"},
    },
)
async def delete_account(
    data: DeleteAccountRequest,
    background_tasks: BackgroundTasks,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    """Executes account soft deletion following identity confirmation."""
    old_avatar = current_user.avatar_url
    result = await IdentityService.delete_account(db, current_user, data, redis)
    if old_avatar:
        background_tasks.add_task(MediaService.cleanup_replaced_urls, [old_avatar], [])
    return MessageResponse(success=True, message=result["message"])


@users_router.get(
    "/me",
    response_model=UserOut,
    summary="Lấy thông tin tài khoản cá nhân hiện tại",
    description="Trả về thông tin chi tiết của người dùng đang đăng nhập (bao gồm trạng thái xác thực email, vai trò hệ thống, trạng thái liên kết Google, số dư ví).",
    responses={
        401: {"description": "Phiên đăng nhập không hợp lệ hoặc đã hết hạn"},
    },
)
async def get_me(current_user: User = Depends(get_current_user)):
    """Returns the profile of the currently authenticated user."""
    return to_user_out(current_user)


@users_router.put(
    "/me",
    response_model=UserOut,
    summary="Cập nhật hồ sơ tài khoản cá nhân",
    description="Cập nhật tên hiển thị, ảnh đại diện hoặc tiểu sử bản thân.",
)
async def update_me(
    data: UserUpdateProfile,
    background_tasks: BackgroundTasks,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Updates profile properties for the currently authenticated user."""
    old_avatar = current_user.avatar_url
    if data.display_name is not None:
        current_user.display_name = data.display_name.strip()
    if data.avatar_url is not None:
        current_user.avatar_url = data.avatar_url.strip() if data.avatar_url.strip() else None
    if data.bio is not None:
        current_user.bio = data.bio.strip() if data.bio.strip() else None

    await db.commit()
    await db.refresh(current_user)

    if data.avatar_url is not None and old_avatar != current_user.avatar_url:
        background_tasks.add_task(
            MediaService.cleanup_replaced_urls,
            [old_avatar],
            [current_user.avatar_url],
        )

    return to_user_out(current_user)


@auth_router.post(
    "/password/change",
    response_model=MessageResponse,
    summary="Đổi mật khẩu tài khoản",
    description="Xác thực mật khẩu cũ và cập nhật mật khẩu mới mã hóa chuẩn Argon2id.",
)
async def change_password(
    data: PasswordChangeRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Changes password for an authenticated user with verification of current password."""
    if not current_user.password_hash or not verify_password(data.old_password, current_user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Mật khẩu hiện tại không chính xác.",
        )
    current_user.password_hash = get_password_hash(data.new_password)
    await db.commit()
    return MessageResponse(success=True, message="Đổi mật khẩu thành công.")

