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
    DevLogin,
    Token,
    UserOut,
    RefreshTokenRequest,
    EmailSendOTPRequest,
    EmailVerifyOTPRequest,
    OAuthSetPasswordRequest,
    DeleteAccountRequest,
    SessionOut,
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


@auth_router.post("/register", response_model=dict, status_code=status.HTTP_201_CREATED)
async def register(
    data: UserRegister,
    request: Request,
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    client_info = extract_client_info(request, data.platform, data.device_id)
    user, tokens = await IdentityService.register(db, data, client_info, redis)
    return {
        "success": True,
        "message": "Đăng ký tài khoản thành công.",
        "tokens": tokens,
        "user": to_user_out(user),
    }


@auth_router.post("/login", response_model=dict)
async def login(
    data: UserLogin,
    request: Request,
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    client_info = extract_client_info(request, data.platform, data.device_id)
    user, tokens = await IdentityService.login(db, data, client_info, redis)
    return {
        "success": True,
        "tokens": tokens,
        "user": to_user_out(user),
    }


@auth_router.post("/google", response_model=dict)
async def google_login(
    data: GoogleLogin,
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    client_info = extract_client_info(request, data.platform, data.device_id)
    user, tokens = await IdentityService.google_login(db, data, client_info)
    return {
        "success": True,
        "tokens": tokens,
        "user": to_user_out(user),
    }


@auth_router.get("/google/login")
async def google_login_url():
    """Generates Google OAuth2 authorization URL for Web/Desktop redirection flow"""
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
    return {"url": auth_url}


@auth_router.get("/google/callback")
async def google_oauth_callback(
    code: str,
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    """Callback endpoint for Google OAuth2 code exchange"""
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
    return {
        "success": True,
        "tokens": tokens,
        "user": to_user_out(user),
    }


@auth_router.post("/dev-login", response_model=dict)
async def dev_login(
    data: DevLogin,
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    client_info = extract_client_info(request, data.platform, data.device_id)
    user, tokens = await IdentityService.dev_login(db, data, client_info)
    return {
        "success": True,
        "tokens": tokens,
        "user": to_user_out(user),
    }


@auth_router.post("/email/send-otp", response_model=dict)
async def send_email_otp(
    data: EmailSendOTPRequest,
    background_tasks: BackgroundTasks,
    redis: aioredis.Redis = Depends(get_redis),
):
    code = await OTPService.send_otp(redis, data.email, data.purpose, background_tasks)
    response_data = {
        "success": True,
        "message": f"Mã OTP xác thực đã được gửi tới {data.email}. Hiệu lực trong 5 phút.",
    }
    if settings.DEBUG and settings.DEBUG_OTP_IN_RESPONSE:
        response_data["dev_otp"] = code
    return response_data


@auth_router.post("/email/verify-otp", response_model=dict)
async def verify_email_otp(
    data: EmailVerifyOTPRequest,
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    await OTPService.verify_otp(redis, data.email, data.code, data.purpose)

    # If purpose is VERIFY_EMAIL, update user is_email_verified
    if data.purpose == OTPPurpose.VERIFY_EMAIL:
        query = select(User).where(User.email == data.email)
        result = await db.execute(query)
        user = result.scalar_one_or_none()
        if user:
            user.is_email_verified = True
            await db.commit()

    return {
        "success": True,
        "message": "Xác thực mã OTP thành công.",
    }


@auth_router.post("/password/oauth-set", response_model=dict)
async def oauth_set_password(
    data: OAuthSetPasswordRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    return await IdentityService.oauth_set_password(db, current_user, data, redis)


@auth_router.post("/refresh", response_model=Token)
async def refresh_access_token(
    data: RefreshTokenRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    client_info = extract_client_info(request)
    return await IdentityService.refresh_token(db, data.refresh_token, client_info)


@auth_router.get("/sessions", response_model=list[SessionOut])
async def list_active_sessions(
    auth_data: tuple[User, uuid.UUID | None] = Depends(get_current_user_and_session),
    db: AsyncSession = Depends(get_db),
):
    user, current_session_id = auth_data
    return await IdentityService.list_sessions(db, user.id, current_session_id)


@auth_router.post("/sessions/{session_id}/revoke", response_model=dict)
async def revoke_session(
    session_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    success = await IdentityService.revoke_session(db, current_user.id, session_id)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Không tìm thấy phiên đăng nhập hoặc bạn không có quyền.",
        )
    return {"success": True, "message": "Thu hồi phiên đăng nhập thành công."}


@auth_router.post("/sessions/revoke-all", response_model=dict)
async def revoke_all_other_sessions(
    auth_data: tuple[User, uuid.UUID | None] = Depends(get_current_user_and_session),
    db: AsyncSession = Depends(get_db),
):
    user, current_session_id = auth_data
    if not current_session_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Không thể xác định phiên đăng nhập hiện tại.",
        )
    revoked_count = await IdentityService.revoke_all_other_sessions(db, user.id, current_session_id)
    return {
        "success": True,
        "message": f"Đã đăng xuất khỏi {revoked_count} thiết bị khác.",
        "revoked_count": revoked_count,
    }


@auth_router.post("/delete-account", response_model=dict)
async def delete_account(
    data: DeleteAccountRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis),
):
    return await IdentityService.delete_account(db, current_user, data, redis)


@users_router.get("/me", response_model=UserOut)
async def get_me(current_user: User = Depends(get_current_user)):
    return to_user_out(current_user)
