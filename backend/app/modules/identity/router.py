"""Identity and Authentication API Router.

This module exposes RESTful endpoints for user registration, multi-platform login,
Google OAuth2 integration, Redis-backed OTP email verification, token refresh rotation,
device session management, and account soft deletion.
"""

import urllib.parse
import uuid
import httpx
from fastapi import APIRouter, Depends, status, Request, BackgroundTasks, HTTPException
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
    Token,
    UserOut,
    RefreshTokenRequest,
    EmailSendOTPRequest,
    EmailVerifyOTPRequest,
    OAuthSetPasswordRequest,
    DeleteAccountRequest,
    SessionOut,
    AuthResponse,
    MessageResponse,
    OTPSendResponse,
    GoogleAuthUrlResponse,
    RevokeAllSessionsResponse,
)
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
    response_model=AuthResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Đăng ký tài khoản người dùng mới",
    description="""
    Khởi tạo tài khoản mới bằng Email và Mật khẩu:
    - **Kiểm tra trùng lặp**: Xác thực tính duy nhất của Email và Username.
    - **Ghi nhận phiên & thiết bị**: Lưu vết IP và User-Agent (với ứng dụng di động bắt buộc kèm `device_id`).
    - **Quy tắc 1 phiên/nền tảng**: Hủy các phiên cũ cùng nền tảng (`MOBILE`, `DESKTOP`, `WEB`).
    - **Ví số dư 0**: Khởi tạo ví tài chính cá nhân với số dư `0` xu ban đầu.
    - **Rate Limit**: Giới hạn tối đa 5 lượt đăng ký trên mỗi địa chỉ IP trong vòng 10 phút.
    """,
    responses={
        400: {"description": "Email hoặc Username đã tồn tại, hoặc thiếu Device ID cho Mobile"},
        429: {"description": "Địa chỉ IP đã vượt quá giới hạn đăng ký cho phép"},
    },
)
async def register(
    data: UserRegister,
    request: Request,
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    """Handles standard user registration and token issuance."""
    client_info = extract_client_info(request, data.platform, data.device_id)
    user, tokens = await IdentityService.register(db, data, client_info, redis)
    return AuthResponse(
        success=True,
        message="Đăng ký tài khoản thành công.",
        tokens=tokens,
        user=to_user_out(user),
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
    Đăng nhập hoặc đăng ký nhanh thông qua Google ID Token:
    - **Xác thực chữ ký số**: Kiểm tra tính hợp lệ của token với máy chủ Google và Client ID.
    - **Tự động liên kết (Auto-link)**: Nếu email Google đã tồn tại trong hệ thống, tự động liên kết `google_id`.
    - **Tạo tài khoản mới**: Nếu chưa tồn tại, tự động tạo tài khoản với role `USER`, ví 0 xu, `is_email_verified = True`.
    """,
    responses={
        400: {"description": "Thiếu thông tin Google ID token hoặc email"},
        401: {"description": "Google ID token không hợp lệ hoặc đã hết hạn"},
    },
)
async def google_login(
    data: GoogleLogin,
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    """Processes Google OAuth authentication and auto-linking."""
    client_info = extract_client_info(request, data.platform, data.device_id)
    user, tokens = await IdentityService.google_login(db, data, client_info)
    return AuthResponse(
        success=True,
        message="Đăng nhập qua Google thành công.",
        tokens=tokens,
        user=to_user_out(user),
    )


@auth_router.get(
    "/google/login",
    response_model=GoogleAuthUrlResponse,
    summary="Lấy URL đăng nhập Google OAuth2 (Web Redirect)",
    description="Tạo đường dẫn cấp quyền của Google OAuth2 cho trình duyệt Web hoặc Desktop.",
)
async def google_login_url():
    """Generates the Google OAuth2 consent screen authorization URL."""
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
    return GoogleAuthUrlResponse(url=auth_url)


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
):
    """Exchanges an authorization code with Google for tokens and logs the user in."""
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
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Lỗi trao đổi mã ủy quyền với Google: {res.text}",
            )
        token_data = res.json()
        id_token_val = token_data.get("id_token")

    client_info = extract_client_info(request)
    user, tokens = await IdentityService.google_login(
        db, GoogleLogin(id_token=id_token_val), client_info
    )
    return AuthResponse(
        success=True,
        message="Xác thực Google OAuth2 thành công.",
        tokens=tokens,
        user=to_user_out(user),
    )


@auth_router.post(
    "/email/send-otp",
    response_model=OTPSendResponse,
    summary="Gửi mã xác thực OTP qua Email",
    description="""
    Sinh mã OTP ngẫu nhiên 6 số và gửi tới email của người dùng:
    - **Lưu trữ Redis**: TTL 5 phút (300 giây).
    - **Chống spam**: Cooldown 60 giây giữa các lần yêu cầu, tối đa 5 mã/giờ.
    - **Mục đích**: `VERIFY_EMAIL`, `OAUTH_SET_PASSWORD`, `RESET_PASSWORD`, `DELETE_ACCOUNT`.
    """,
    responses={
        429: {"description": "Đang trong thời gian chờ cooldown 60s hoặc đã vượt quá 5 mã/giờ"},
    },
)
async def send_email_otp(
    data: EmailSendOTPRequest,
    background_tasks: BackgroundTasks,
    redis: aioredis.Redis = Depends(get_redis),
):
    """Generates and sends an OTP code via email in background."""
    code = await OTPService.send_otp(redis, data.email, data.purpose, background_tasks)
    return OTPSendResponse(
        success=True,
        message=f"Mã OTP xác thực đã được gửi tới {data.email}. Hiệu lực trong 5 phút.",
        dev_otp=code if (settings.DEBUG and settings.DEBUG_OTP_IN_RESPONSE) else None,
    )


@auth_router.post(
    "/email/verify-otp",
    response_model=MessageResponse,
    summary="Xác thực mã OTP và kích hoạt tài khoản",
    description="""
    Xác nhận mã OTP 6 số người dùng nhập:
    - **Single-use**: Mã bị hủy ngay sau khi xác thực thành công.
    - **Chống Brute-force**: Hủy mã nếu nhập sai quá 5 lần liên tiếp.
    - **Kích hoạt tài khoản**: Nếu mục đích là `VERIFY_EMAIL`, cập nhật `is_email_verified = True`.
    """,
    responses={
        400: {"description": "Mã OTP không tồn tại, hết hạn, hoặc nhập sai"},
    },
)
async def verify_email_otp(
    data: EmailVerifyOTPRequest,
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    """Verifies an OTP and activates the user's email if valid."""
    await OTPService.verify_otp(redis, data.email, data.code, data.purpose)

    if data.purpose == OTPPurpose.VERIFY_EMAIL:
        query = select(User).where(User.email == data.email)
        result = await db.execute(query)
        user = result.scalar_one_or_none()
        if user:
            user.is_email_verified = True
            await db.commit()

    return MessageResponse(
        success=True,
        message="Xác thực mã OTP thành công. Tài khoản đã được kích hoạt.",
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
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    """Executes account soft deletion following identity confirmation."""
    result = await IdentityService.delete_account(db, current_user, data, redis)
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
