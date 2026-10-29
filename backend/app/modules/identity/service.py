"""Identity and Authentication Business Logic Service.

This module implements the core business logic for user registration, credential
verification, multi-platform device session enforcement, Google OAuth2 account auto-linking,
password establishment for OAuth profiles, and remote session revocation.
"""

import json
import uuid
from datetime import datetime, timezone, timedelta
from typing import Callable
from fastapi import BackgroundTasks, HTTPException, status, Depends
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
import redis.asyncio as aioredis
from google.oauth2 import id_token as google_id_token
from google.auth.transport import requests as google_requests

from app.core.config import get_settings
from app.core.database import get_db
from app.core.redis import get_redis
from app.core.security import (
    get_password_hash,
    verify_password,
    create_access_token,
    create_refresh_token,
    decode_token,
    hash_token,
)
from app.core.client_detector import ClientInfo
from app.core.rate_limiter import RateLimiter
from app.modules.identity.models import User, UserSession, SystemRole
from app.modules.billing.models import Wallet
from app.modules.identity.schemas import (
    UserRegister,
    UserLogin,
    GoogleLogin,
    GoogleLinkRequest,
    OAuthSetPasswordRequest,
    DeleteAccountRequest,
    Token,
    SessionOut,
)
from app.modules.identity.otp_service import OTPService, OTPPurpose

settings = get_settings()
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")


class IdentityService:
    """Encapsulates authentication, session management, and credential business logic."""

    @staticmethod
    async def enforce_single_platform_session(
        db: AsyncSession, user_id: uuid.UUID, platform: str
    ) -> None:
        """Enforces the Single Active Session per Platform policy.

        Invalidates any existing active session of the specified user on the target
        platform ('MOBILE', 'DESKTOP', or 'WEB'). Sessions on other platforms remain untouched.

        Args:
            db (AsyncSession): Active asynchronous database session.
            user_id (uuid.UUID): ID of the user whose platform sessions are evaluated.
            platform (str): The platform category ('MOBILE', 'DESKTOP', or 'WEB').
        """
        stmt = (
            update(UserSession)
            .where(
                UserSession.user_id == user_id,
                UserSession.platform == platform,
                UserSession.is_active == True,
            )
            .values(is_active=False)
        )
        await db.execute(stmt)

    @classmethod
    async def register(
        cls,
        db: AsyncSession,
        data: UserRegister,
        client_info: ClientInfo,
        redis: aioredis.Redis,
        background_tasks: BackgroundTasks,
    ) -> str:
        """Stages a new user registration request in Redis and dispatches an OTP email.

        Does NOT insert into PostgreSQL or issue JWT tokens until the user verifies
        ownership of the email via the 6-digit OTP code. The staged request automatically
        expires after `settings.PENDING_REGISTRATION_TTL_SECONDS` (default 10 minutes).

        Args:
            db (AsyncSession): Database session to check existing accounts.
            data (UserRegister): Registration input data.
            client_info (ClientInfo): Parsed client IP and device metadata.
            redis (aioredis.Redis): Redis client for rate limiting and staging.
            background_tasks (BackgroundTasks): FastAPI background task manager for SMTP dispatch.

        Returns:
            str: The generated 6-digit OTP code.

        Raises:
            HTTPException: 429 if IP rate limit or OTP cooldown is exceeded.
            HTTPException: 400 if email or username is already registered or reserved.
        """
        clean_email = str(data.email).strip().lower()
        clean_username = data.username.strip()
        clean_username_lower = clean_username.lower()

        # 1. Check existing email or username in PostgreSQL first
        query = select(User).where((User.email == clean_email) | (User.username == clean_username))
        result = await db.execute(query)
        if result.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email hoặc Tên tài khoản (username) đã được sử dụng.",
            )

        # 2. Check if username is currently reserved by another pending registration in Redis
        username_res_key = f"pending_reg:username:{clean_username_lower}"
        reserved_by_email = await redis.get(username_res_key)
        if reserved_by_email and reserved_by_email != clean_email:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Tên tài khoản (username) này đang được giữ chỗ bởi một yêu cầu đăng ký khác. Vui lòng chọn tên khác hoặc thử lại sau 10 phút.",
            )

        # 3. Enforce IP registration rate limit
        await RateLimiter.check_register_limit(redis, client_info.ip_address)

        # 4. Generate and send 6-digit OTP email (enforces 60s cooldown & 5/hr quota)
        otp_code = await OTPService.send_otp(
            redis, clean_email, OTPPurpose.VERIFY_EMAIL, background_tasks
        )

        # 5. Clean up old username reservation if this email previously staged a different username
        pending_email_key = f"pending_reg:email:{clean_email}"
        old_raw = await redis.get(pending_email_key)
        if old_raw:
            try:
                old_data = json.loads(old_raw)
                old_uname = old_data.get("username", "").lower()
                if old_uname and old_uname != clean_username_lower:
                    await redis.delete(f"pending_reg:username:{old_uname}")
            except Exception:
                pass

        # 6. Stage registration payload in Redis with auto-cancel TTL (10 minutes)
        staged_payload = {
            "email": clean_email,
            "username": clean_username,
            "password_hash": get_password_hash(data.password),
            "display_name": data.display_name.strip(),
            "platform": client_info.platform,
            "device_id": client_info.device_id,
            "device_name": client_info.device_name,
            "ip_address": client_info.ip_address,
            "user_agent": client_info.user_agent,
        }
        ttl = settings.PENDING_REGISTRATION_TTL_SECONDS
        await redis.set(pending_email_key, json.dumps(staged_payload), ex=ttl)
        await redis.set(username_res_key, clean_email, ex=ttl)

        return otp_code

    @classmethod
    async def complete_registration(
        cls,
        db: AsyncSession,
        redis: aioredis.Redis,
        email: str,
        code: str,
    ) -> tuple[User, Token]:
        """Verifies the registration OTP and provisions the User, Wallet, and Session in PostgreSQL.

        Args:
            db (AsyncSession): Active asynchronous database session.
            redis (aioredis.Redis): Active Redis connection holding staged registration & OTP.
            email (str): Email address being verified.
            code (str): 6-digit OTP code submitted by the user.

        Returns:
            tuple[User, Token]: Created User entity and initial JWT Token bundle.

        Raises:
            HTTPException: 400 if staged registration has expired/does not exist, OTP is invalid,
                or email/username was claimed concurrently.
        """
        clean_email = email.strip().lower()
        pending_email_key = f"pending_reg:email:{clean_email}"

        # 1. Ensure staged registration exists and hasn't auto-expired (10m TTL)
        raw_pending = await redis.get(pending_email_key)
        if not raw_pending:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Yêu cầu đăng ký không tồn tại hoặc đã tự hủy do quá thời hạn (10 phút). Vui lòng đăng ký lại.",
            )

        # 2. Verify OTP code (revokes both OTP and pending_reg if 5 wrong attempts are reached)
        await OTPService.verify_otp(redis, clean_email, code, OTPPurpose.VERIFY_EMAIL)

        try:
            staged = json.loads(raw_pending)
        except Exception:
            await redis.delete(pending_email_key)
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Dữ liệu đăng ký tạm thời không hợp lệ. Vui lòng đăng ký lại.",
            )

        username = staged["username"]
        username_res_key = f"pending_reg:username:{username.lower()}"

        # 3. Double-check uniqueness in PostgreSQL against race conditions
        query = select(User).where((User.email == clean_email) | (User.username == username))
        result = await db.execute(query)
        if result.scalar_one_or_none():
            await redis.delete(pending_email_key)
            await redis.delete(username_res_key)
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email hoặc Tên tài khoản (username) đã được sử dụng.",
            )

        # 4. Provision verified User & 0-balance Wallet in PostgreSQL
        user = User(
            email=clean_email,
            username=username,
            password_hash=staged["password_hash"],
            display_name=staged["display_name"],
            system_role=SystemRole.USER.value,
            is_email_verified=True,
            is_active=True,
        )
        db.add(user)
        await db.flush()

        wallet = Wallet(user_id=user.id, coin_balance=0)
        db.add(wallet)

        # 5. Enforce single active session per platform & issue JWT tokens
        platform = staged.get("platform") or "WEB"
        await cls.enforce_single_platform_session(db, user.id, platform)

        session_id = uuid.uuid4()
        access_token = create_access_token({
            "sub": str(user.id),
            "username": user.username,
            "session_id": str(session_id),
            "system_role": user.system_role,
        })
        refresh_token = create_refresh_token({
            "sub": str(user.id),
            "session_id": str(session_id),
        })

        session = UserSession(
            id=session_id,
            user_id=user.id,
            platform=platform,
            device_id=staged.get("device_id"),
            device_name=staged.get("device_name") or "Web Browser",
            ip_address=staged.get("ip_address"),
            user_agent=staged.get("user_agent"),
            refresh_token_hash=hash_token(refresh_token),
            is_active=True,
            expires_at=datetime.now(timezone.utc) + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS),
        )
        db.add(session)
        await db.commit()
        await db.refresh(user, ["wallet"])

        # 6. Delete staged keys from Redis immediately
        await redis.delete(pending_email_key)
        await redis.delete(username_res_key)

        tokens = Token(
            access_token=access_token,
            refresh_token=refresh_token,
            session_id=session_id,
        )
        return user, tokens

    @classmethod
    async def login(
        cls,
        db: AsyncSession,
        data: UserLogin,
        client_info: ClientInfo,
        redis: aioredis.Redis,
    ) -> tuple[User, Token]:
        """Authenticates a user via email and password credentials.

        Checks account lockout thresholds, validates the password against stored Argon2id hash,
        enforces the single-platform session rule, and issues new tokens.

        Args:
            db (AsyncSession): Database session.
            data (UserLogin): User credentials.
            client_info (ClientInfo): Parsed client IP and device metadata.
            redis (aioredis.Redis): Redis client for lockout tracking.

        Returns:
            tuple[User, Token]: Authenticated user entity and token bundle.

        Raises:
            HTTPException: 429 if the account is currently locked out.
            HTTPException: 400 if the account was provisioned via OAuth and has not established a password.
            HTTPException: 401 if credentials are invalid or password mismatch.
        """
        clean_email = str(data.email).strip().lower()

        # 1. Check lockout rate limit
        await RateLimiter.check_login_lockout(redis, clean_email)

        # 2. Look up user
        query = (
            select(User)
            .where(User.email == clean_email, User.is_active == True)
            .options(selectinload(User.wallet))
        )
        result = await db.execute(query)
        user = result.scalar_one_or_none()

        if not user:
            await RateLimiter.record_login_failure(redis, clean_email)
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Email hoặc mật khẩu không chính xác.",
            )

        # Reject password authentication for OAuth-provisioned accounts without a password set
        if not user.password_hash:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Tài khoản này được tạo qua Google và chưa thiết lập mật khẩu. Vui lòng đăng nhập bằng Google để tiếp tục và cài đặt mật khẩu.",
            )

        if not verify_password(data.password, user.password_hash):
            await RateLimiter.record_login_failure(redis, clean_email)
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Email hoặc mật khẩu không chính xác.",
            )

        # 3. Clear failed login attempts on success
        await RateLimiter.clear_login_failure(redis, clean_email)

        # 4. Enforce Single Platform Session rule
        await cls.enforce_single_platform_session(db, user.id, client_info.platform)

        # 5. Create new session & issue tokens
        session_id = uuid.uuid4()
        access_token = create_access_token({
            "sub": str(user.id),
            "username": user.username,
            "session_id": str(session_id),
            "system_role": user.system_role,
        })
        refresh_token = create_refresh_token({
            "sub": str(user.id),
            "session_id": str(session_id),
        })

        session = UserSession(
            id=session_id,
            user_id=user.id,
            platform=client_info.platform,
            device_id=client_info.device_id,
            device_name=client_info.device_name,
            ip_address=client_info.ip_address,
            user_agent=client_info.user_agent,
            refresh_token_hash=hash_token(refresh_token),
            is_active=True,
            expires_at=datetime.now(timezone.utc) + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS),
        )
        db.add(session)
        await db.commit()
        await db.refresh(user, ["wallet"])

        tokens = Token(
            access_token=access_token,
            refresh_token=refresh_token,
            session_id=session_id,
        )
        return user, tokens

    @staticmethod
    def verify_google_id_token(id_token_str: str) -> dict:
        """Strictly verifies a Google JWT ID token against Google's public JWKS keys.

        Args:
            id_token_str (str): The raw Google ID token string.

        Returns:
            dict: Verified claims containing `sub`, `email`, `name`, and `picture`.

        Raises:
            HTTPException: 500 if GOOGLE_CLIENT_ID is missing.
            HTTPException: 401 if token signature, audience, expiry, issuer, or email_verified check fails.
        """
        if not settings.GOOGLE_CLIENT_ID:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Hệ thống chưa cấu hình GOOGLE_CLIENT_ID để xác thực Google OAuth.",
            )

        try:
            id_info = google_id_token.verify_oauth2_token(
                id_token_str, google_requests.Request(), settings.GOOGLE_CLIENT_ID
            )
        except Exception as e:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=f"Mã Google ID token không hợp lệ hoặc đã hết hạn: {str(e)}",
            )

        if id_info.get("iss") not in ("accounts.google.com", "https://accounts.google.com"):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Nhà phát hành (issuer) của Google ID token không hợp lệ.",
            )

        google_sub = id_info.get("sub")
        google_email = id_info.get("email")
        email_verified = id_info.get("email_verified", False)

        if not google_sub or not google_email or not email_verified:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Tài khoản Google không hợp lệ hoặc email chưa được Google xác minh.",
            )

        clean_email = google_email.strip().lower()
        return {
            "sub": google_sub,
            "email": clean_email,
            "name": id_info.get("name") or clean_email.split("@")[0],
            "picture": id_info.get("picture"),
        }

    @classmethod
    async def link_google_account(
        cls,
        db: AsyncSession,
        user: User,
        data: GoogleLinkRequest,
    ) -> User:
        """Links a verified Google identity to an authenticated user account.

        Args:
            db (AsyncSession): Database session.
            user (User): Currently authenticated user entity.
            data (GoogleLinkRequest): Payload containing the Google ID token.

        Returns:
            User: Updated user entity with `google_id` linked.

        Raises:
            HTTPException: 400 if the user is already linked to Google, the Google account
                belongs to another user, or the Google email does not match the user's email.
            HTTPException: 401 if Google ID token verification fails.
        """
        google_info = cls.verify_google_id_token(data.id_token)
        google_sub = google_info["sub"]
        google_email = google_info["email"]
        avatar_url = google_info["picture"]

        if user.google_id:
            if user.google_id == google_sub:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Tài khoản của bạn đã được liên kết với tài khoản Google này rồi.",
                )
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Tài khoản của bạn đã được liên kết với một tài khoản Google khác.",
            )

        # Ensure this google_sub is not already linked to another user
        existing_sub_query = select(User).where(User.google_id == google_sub, User.id != user.id)
        existing_sub_res = await db.execute(existing_sub_query)
        if existing_sub_res.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Tài khoản Google này đã được liên kết với một người dùng khác.",
            )

        if google_email.lower() != user.email.lower():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email của tài khoản Google phải trùng khớp với email tài khoản hiện tại của bạn.",
            )

        user.google_id = google_sub
        user.is_email_verified = True
        if not user.avatar_url and avatar_url:
            user.avatar_url = avatar_url

        await db.commit()
        await db.refresh(user, ["wallet"])
        return user

    @classmethod
    async def google_login(
        cls,
        db: AsyncSession,
        data: GoogleLogin,
        client_info: ClientInfo,
        redis: aioredis.Redis | None = None,
    ) -> tuple[User, Token]:
        """Authenticates or provisions a user account via Google OAuth2.

        - Existing `google_id` match: Authenticates the user directly.
        - Existing `email` match (unlinked account): Requires `data.password` to verify
          ownership of the existing account before linking `google_id`. Raises `409 Conflict`
          if `data.password` is omitted.
        - New email: Automatically provisions a new user account with `password_hash=None`
          and `is_email_verified=True`.

        Args:
            db (AsyncSession): Database session.
            data (GoogleLogin): Google OAuth payload with optional password confirmation.
            client_info (ClientInfo): Parsed client IP and device metadata.
            redis (aioredis.Redis | None): Optional Redis client for lockout enforcement during password verification.

        Returns:
            tuple[User, Token]: Authenticated user entity and token bundle.
        """
        google_info = cls.verify_google_id_token(data.id_token)
        google_sub = google_info["sub"]
        google_email = google_info["email"]
        display_name = google_info["name"]
        avatar_url = google_info["picture"]

        # 1. Check if user already exists by google_id
        query = (
            select(User)
            .where(User.google_id == google_sub, User.is_active == True)
            .options(selectinload(User.wallet))
        )
        result = await db.execute(query)
        user = result.scalar_one_or_none()

        # 2. Check if user exists by email (not yet linked to this google_sub)
        if not user:
            query = (
                select(User)
                .where(User.email == google_email, User.is_active == True)
                .options(selectinload(User.wallet))
            )
            result = await db.execute(query)
            user = result.scalar_one_or_none()
            if user:
                if user.google_id and user.google_id != google_sub:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail="Email này đã được liên kết với một định danh Google khác.",
                    )

                # Require password verification before linking an existing unlinked account
                if not data.password:
                    raise HTTPException(
                        status_code=status.HTTP_409_CONFLICT,
                        detail="Email này đã được đăng ký bằng mật khẩu. Vui lòng nhập mật khẩu của tài khoản hiện có để xác nhận liên kết với Google.",
                    )

                if redis:
                    await RateLimiter.check_login_lockout(redis, google_email)

                if not user.password_hash or not verify_password(data.password, user.password_hash):
                    if redis:
                        await RateLimiter.record_login_failure(redis, google_email)
                    raise HTTPException(
                        status_code=status.HTTP_401_UNAUTHORIZED,
                        detail="Mật khẩu xác nhận liên kết tài khoản không chính xác.",
                    )

                if redis:
                    await RateLimiter.clear_login_failure(redis, google_email)

                user.google_id = google_sub
                user.is_email_verified = True
                if not user.avatar_url and avatar_url:
                    user.avatar_url = avatar_url
                await db.flush()

        # 3. Provision a new account if no matching user exists
        if not user:
            base_username = google_email.split("@")[0][:40]
            username = f"{base_username}_{uuid.uuid4().hex[:6]}"
            user = User(
                email=google_email,
                username=username,
                display_name=display_name,
                avatar_url=avatar_url,
                google_id=google_sub,
                is_email_verified=True,
                system_role=SystemRole.USER.value,
                password_hash=None,
                is_active=True,
            )
            db.add(user)
            await db.flush()

            wallet = Wallet(user_id=user.id, coin_balance=0)
            db.add(wallet)

        # 4. Enforce single platform session
        await cls.enforce_single_platform_session(db, user.id, client_info.platform)

        # 5. Issue tokens & session
        session_id = uuid.uuid4()
        access_token = create_access_token({
            "sub": str(user.id),
            "username": user.username,
            "session_id": str(session_id),
            "system_role": user.system_role,
        })
        refresh_token = create_refresh_token({
            "sub": str(user.id),
            "session_id": str(session_id),
        })

        session = UserSession(
            id=session_id,
            user_id=user.id,
            platform=client_info.platform,
            device_id=client_info.device_id,
            device_name=client_info.device_name,
            ip_address=client_info.ip_address,
            user_agent=client_info.user_agent,
            refresh_token_hash=hash_token(refresh_token),
            is_active=True,
            expires_at=datetime.now(timezone.utc) + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS),
        )
        db.add(session)
        await db.commit()
        await db.refresh(user, ["wallet"])

        tokens = Token(
            access_token=access_token,
            refresh_token=refresh_token,
            session_id=session_id,
        )
        return user, tokens

    @staticmethod
    async def oauth_set_password(
        db: AsyncSession,
        user: User,
        data: OAuthSetPasswordRequest,
        redis: aioredis.Redis,
    ) -> dict:
        """Establishes a password on an OAuth-provisioned account following OTP verification.

        Args:
            db (AsyncSession): Database session.
            user (User): The authenticated OAuth user.
            data (OAuthSetPasswordRequest): Candidate OTP and desired new password.
            redis (aioredis.Redis): Redis client for OTP verification.

        Returns:
            dict: Success confirmation message.

        Raises:
            HTTPException: 400 if account already has a password, or OTP is incorrect/expired.
        """
        if user.password_hash:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Tài khoản đã thiết lập mật khẩu trước đó. Vui lòng sử dụng chức năng đổi mật khẩu.",
            )
        await OTPService.verify_otp(redis, user.email, data.otp, OTPPurpose.OAUTH_SET_PASSWORD)
        user.password_hash = get_password_hash(data.new_password)
        await db.commit()
        return {"success": True, "message": "Thiết lập mật khẩu thành công. Bạn có thể đăng nhập bằng cả Google và Email/Mật khẩu."}

    @staticmethod
    async def delete_account(
        db: AsyncSession,
        user: User,
        data: DeleteAccountRequest,
        redis: aioredis.Redis,
    ) -> dict:
        """Executes soft account deletion and revokes all active device sessions.

        Requires password confirmation if the account has a password set, or email
        OTP verification if the account is purely social OAuth.

        Args:
            db (AsyncSession): Database session.
            user (User): The user requesting account deletion.
            data (DeleteAccountRequest): Password or OTP verification credentials.
            redis (aioredis.Redis): Redis client for OTP verification.

        Returns:
            dict: Success confirmation message.

        Raises:
            HTTPException: 400 if confirmation password or OTP is missing or incorrect.
        """
        if user.password_hash:
            if not data.password or not verify_password(data.password, user.password_hash):
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Mật khẩu xác nhận không chính xác.",
                )
        else:
            if not data.otp:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Tài khoản đăng nhập mạng xã hội cần cung cấp mã OTP gửi về email để xác nhận xóa.",
                )
            await OTPService.verify_otp(redis, user.email, data.otp, OTPPurpose.DELETE_ACCOUNT)

        # Invalidate all active sessions across all platforms
        stmt = (
            update(UserSession)
            .where(UserSession.user_id == user.id)
            .values(is_active=False)
        )
        await db.execute(stmt)

        # Soft delete user
        user.is_active = False
        user.deleted_at = datetime.now(timezone.utc)
        user.email = f"deleted_{user.id.hex[:8]}_{user.email}"
        user.username = f"deleted_{user.id.hex[:8]}_{user.username}"
        user.google_id = None
        await db.commit()

        return {"success": True, "message": "Tài khoản của bạn đã được xóa thành công."}

    @staticmethod
    async def refresh_token(
        db: AsyncSession,
        refresh_token_str: str,
        client_info: ClientInfo,
    ) -> Token:
        """Rotates a refresh token and issues a new access token.

        Validates session existence and verifies that the refresh token hash matches
        the active session record. Immediately rotates the refresh token material
        to protect against token replay/theft attacks.

        Args:
            db (AsyncSession): Database session.
            refresh_token_str (str): Raw refresh token JWT presented by the client.
            client_info (ClientInfo): Parsed client IP and device metadata.

        Returns:
            Token: Fresh token bundle containing new access token and rotated refresh token.

        Raises:
            HTTPException: 401 if token is expired, invalid, or replayed.
        """
        credentials_exception = HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Phiên làm việc không hợp lệ hoặc đã hết hạn.",
            headers={"WWW-Authenticate": "Bearer"},
        )
        try:
            payload = decode_token(refresh_token_str)
            if payload.get("type") != "refresh":
                raise credentials_exception
            user_id_str = payload.get("sub")
            session_id_str = payload.get("session_id")
            if not user_id_str or not session_id_str:
                raise credentials_exception
            user_id = uuid.UUID(user_id_str)
            session_id = uuid.UUID(session_id_str)
        except Exception:
            raise credentials_exception

        # Look up session
        query = select(UserSession).where(
            UserSession.id == session_id,
            UserSession.user_id == user_id,
            UserSession.is_active == True,
        )
        result = await db.execute(query)
        session = result.scalar_one_or_none()

        if not session or session.expires_at < datetime.now(timezone.utc):
            raise credentials_exception

        # Verify refresh token hash to guard against token theft / reuse
        if session.refresh_token_hash != hash_token(refresh_token_str):
            session.is_active = False
            await db.commit()
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token không khớp. Phiên làm việc đã bị vô hiệu hóa vì lý do bảo mật.",
            )

        # Look up user to refresh claims
        user_query = select(User).where(User.id == user_id, User.is_active == True)
        user_res = await db.execute(user_query)
        user = user_res.scalar_one_or_none()
        if not user:
            raise credentials_exception

        # Rotate tokens: issue new access token & new refresh token
        new_access = create_access_token({
            "sub": str(user.id),
            "username": user.username,
            "session_id": str(session.id),
            "system_role": user.system_role,
        })
        new_refresh = create_refresh_token({
            "sub": str(user.id),
            "session_id": str(session.id),
        })

        session.refresh_token_hash = hash_token(new_refresh)
        session.last_active_at = datetime.now(timezone.utc)
        session.ip_address = client_info.ip_address
        await db.commit()

        return Token(
            access_token=new_access,
            refresh_token=new_refresh,
            session_id=session.id,
        )

    @staticmethod
    async def list_sessions(
        db: AsyncSession, user_id: uuid.UUID, current_session_id: uuid.UUID | None
    ) -> list[SessionOut]:
        """Lists all active device sessions for a user account.

        Args:
            db (AsyncSession): Database session.
            user_id (uuid.UUID): ID of the user whose sessions to retrieve.
            current_session_id (uuid.UUID | None): ID of the active caller session.

        Returns:
            list[SessionOut]: Active session metadata ordered by last activity time.
        """
        query = (
            select(UserSession)
            .where(UserSession.user_id == user_id, UserSession.is_active == True)
            .order_by(UserSession.last_active_at.desc())
        )
        result = await db.execute(query)
        sessions = result.scalars().all()
        return [
            SessionOut(
                id=s.id,
                platform=s.platform,
                device_id=s.device_id,
                device_name=s.device_name,
                ip_address=s.ip_address,
                is_active=s.is_active,
                last_active_at=s.last_active_at,
                created_at=s.created_at,
                is_current=(s.id == current_session_id),
            )
            for s in sessions
        ]

    @staticmethod
    async def revoke_session(
        db: AsyncSession, user_id: uuid.UUID, session_id: uuid.UUID
    ) -> bool:
        """Revokes a specific device session owned by the user.

        Args:
            db (AsyncSession): Database session.
            user_id (uuid.UUID): ID of the user who owns the session.
            session_id (uuid.UUID): ID of the session to terminate.

        Returns:
            bool: True if the session was found and deactivated, False otherwise.
        """
        stmt = (
            update(UserSession)
            .where(UserSession.id == session_id, UserSession.user_id == user_id)
            .values(is_active=False)
        )
        result = await db.execute(stmt)
        await db.commit()
        return result.rowcount > 0

    @staticmethod
    async def revoke_all_other_sessions(
        db: AsyncSession, user_id: uuid.UUID, current_session_id: uuid.UUID
    ) -> int:
        """Terminates all active device sessions for a user except the current session.

        Args:
            db (AsyncSession): Database session.
            user_id (uuid.UUID): ID of the user.
            current_session_id (uuid.UUID): The session to keep active.

        Returns:
            int: The number of sessions that were deactivated.
        """
        stmt = (
            update(UserSession)
            .where(
                UserSession.user_id == user_id,
                UserSession.id != current_session_id,
                UserSession.is_active == True,
            )
            .values(is_active=False)
        )
        result = await db.execute(stmt)
        await db.commit()
        return result.rowcount


async def get_current_user_and_session(
    token: str = Depends(oauth2_scheme),
    db: AsyncSession = Depends(get_db),
) -> tuple[User, uuid.UUID | None]:
    """Dependency validating JWT access tokens and confirming device session validity.

    Args:
        token (str): Injected Bearer token from HTTP Authorization header.
        db (AsyncSession): Injected database session.

    Returns:
        tuple[User, uuid.UUID | None]: The authenticated User and their session ID.

    Raises:
        HTTPException: 401 if token is expired, invalid, user inactive, or session revoked.
    """
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Phiên đăng nhập không hợp lệ hoặc đã hết hạn.",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = decode_token(token)
        user_id_str: str = payload.get("sub")
        if user_id_str is None:
            raise credentials_exception
        user_id = uuid.UUID(user_id_str)
        session_id_str = payload.get("session_id")
        session_id = uuid.UUID(session_id_str) if session_id_str else None
    except Exception:
        raise credentials_exception

    query = (
        select(User)
        .where(User.id == user_id, User.is_active == True)
        .options(selectinload(User.wallet))
    )
    result = await db.execute(query)
    user = result.scalar_one_or_none()
    if user is None:
        raise credentials_exception

    # Check if session was revoked
    if session_id:
        sess_query = select(UserSession).where(
            UserSession.id == session_id,
            UserSession.is_active == True,
        )
        sess_res = await db.execute(sess_query)
        if not sess_res.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Phiên làm việc trên thiết bị này đã bị đăng xuất.",
                headers={"WWW-Authenticate": "Bearer"},
            )

    return user, session_id


async def get_current_user(
    auth_data: tuple[User, uuid.UUID | None] = Depends(get_current_user_and_session)
) -> User:
    """Dependency extracting the authenticated User from verified token claims.

    Args:
        auth_data (tuple[User, uuid.UUID | None]): Resolved user and session from parent dependency.

    Returns:
        User: Active authenticated user entity.
    """
    return auth_data[0]


def require_system_role(*allowed_roles: str) -> Callable:
    """Dependency factory enforcing system-level role-based access control.

    Args:
        *allowed_roles (str): Variable list of required SystemRole names.

    Returns:
        Callable: FastAPI dependency function validating that current user has an allowed role.
    """
    async def role_checker(user: User = Depends(get_current_user)) -> User:
        if user.system_role not in allowed_roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Bạn không có quyền quản trị để thực hiện thao tác này.",
            )
        return user
    return role_checker
