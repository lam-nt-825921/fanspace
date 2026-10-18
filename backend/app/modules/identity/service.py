"""Identity and Authentication Business Logic Service.

This module implements the core business logic for user registration, credential
verification, multi-platform device session enforcement, Google OAuth2 account auto-linking,
password establishment for OAuth profiles, and remote session revocation.
"""

import uuid
from datetime import datetime, timezone, timedelta
from typing import Callable
from fastapi import HTTPException, status, Depends
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
    ) -> tuple[User, Token]:
        """Registers a new standard user account with email and password.

        Enforces IP rate limiting, checks for email and username uniqueness,
        initializes the user wallet with 0 balance, and issues a new session.

        Args:
            db (AsyncSession): Database session.
            data (UserRegister): Registration input data.
            client_info (ClientInfo): Parsed client IP and device metadata.
            redis (aioredis.Redis): Redis client for rate limiting.

        Returns:
            tuple[User, Token]: Created user entity and initial token bundle.

        Raises:
            HTTPException: 429 if the IP rate limit is exceeded.
            HTTPException: 400 if email or username already exists.
        """
        # 1. Rate limiting by IP
        await RateLimiter.check_register_limit(redis, client_info.ip_address)

        # 2. Check existing email or username
        query = select(User).where((User.email == data.email) | (User.username == data.username))
        result = await db.execute(query)
        if result.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email hoặc Tên tài khoản (username) đã được sử dụng.",
            )

        # 3. Hash password & create user
        hashed_pwd = get_password_hash(data.password)
        user = User(
            email=data.email,
            username=data.username,
            password_hash=hashed_pwd,
            display_name=data.display_name,
            system_role=SystemRole.USER.value,
            is_email_verified=False,
            is_active=True,
        )
        db.add(user)
        await db.flush()

        # 4. Create wallet with 0 coins initial balance (Real money rule)
        wallet = Wallet(user_id=user.id, coin_balance=0)
        db.add(wallet)

        # 5. Single session per platform
        await cls.enforce_single_platform_session(db, user.id, client_info.platform)

        # 6. Issue tokens & create UserSession
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
            HTTPException: 401 if credentials are invalid or password mismatch.
        """
        # 1. Check lockout rate limit
        await RateLimiter.check_login_lockout(redis, data.email)

        # 2. Look up user
        query = (
            select(User)
            .where(User.email == data.email, User.is_active == True)
            .options(selectinload(User.wallet))
        )
        result = await db.execute(query)
        user = result.scalar_one_or_none()

        if not user or not user.password_hash or not verify_password(data.password, user.password_hash):
            await RateLimiter.record_login_failure(redis, data.email)
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Email hoặc mật khẩu không chính xác.",
            )

        # 3. Clear failed login attempts on success
        await RateLimiter.clear_login_failure(redis, data.email)

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

    @classmethod
    async def google_login(
        cls,
        db: AsyncSession,
        data: GoogleLogin,
        client_info: ClientInfo,
    ) -> tuple[User, Token]:
        """Authenticates or registers a user via Google OAuth2.

        Verifies the Google ID token. If the Google subject ID or email is already
        registered, automatically links the Google account. If brand new, provisions
        a new user account with `is_email_verified=True` and wallet balance of 0.

        Args:
            db (AsyncSession): Database session.
            data (GoogleLogin): Google OAuth payload.
            client_info (ClientInfo): Parsed client IP and device metadata.

        Returns:
            tuple[User, Token]: Logged in user entity and token bundle.

        Raises:
            HTTPException: 401 if Google ID token verification fails.
            HTTPException: 400 if required token or email is absent.
        """
        google_sub = None
        google_email = None
        display_name = data.display_name or "Google User"
        avatar_url = data.avatar_url

        # 1. Verify Google ID token if provided
        if data.id_token and settings.GOOGLE_CLIENT_ID:
            try:
                id_info = google_id_token.verify_oauth2_token(
                    data.id_token, google_requests.Request(), settings.GOOGLE_CLIENT_ID
                )
                google_sub = id_info.get("sub")
                google_email = id_info.get("email")
                display_name = id_info.get("name", display_name)
                avatar_url = id_info.get("picture", avatar_url)
            except Exception as e:
                if not settings.DEBUG:
                    raise HTTPException(
                        status_code=status.HTTP_401_UNAUTHORIZED,
                        detail=f"Mã Google ID token không hợp lệ: {str(e)}",
                    )
                google_sub = data.id_token[:40]
                google_email = str(data.email) if data.email else f"google_{google_sub}@gmail.com"
        else:
            if not data.email:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Cần cung cấp Google ID token hoặc email để đăng nhập.",
                )
            google_email = str(data.email)
            google_sub = f"mock_google_{google_email}"

        # 2. Check if user already exists by google_id
        user = None
        if google_sub:
            query = select(User).where(User.google_id == google_sub, User.is_active == True).options(selectinload(User.wallet))
            result = await db.execute(query)
            user = result.scalar_one_or_none()

        # 3. Check if user exists by email -> Auto-link!
        if not user and google_email:
            query = select(User).where(User.email == google_email, User.is_active == True).options(selectinload(User.wallet))
            result = await db.execute(query)
            user = result.scalar_one_or_none()
            if user:
                user.google_id = google_sub
                user.is_email_verified = True
                if not user.avatar_url and avatar_url:
                    user.avatar_url = avatar_url
                await db.flush()

        # 4. If user still doesn't exist -> Create new account
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

            # Wallet balance: 0 coins
            wallet = Wallet(user_id=user.id, coin_balance=0)
            db.add(wallet)

        # 5. Enforce single platform session
        await cls.enforce_single_platform_session(db, user.id, client_info.platform)

        # 6. Issue tokens & session
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
        """Sets a password on an OAuth-registered account following OTP verification.

        Args:
            db (AsyncSession): Database session.
            user (User): The authenticated OAuth user.
            data (OAuthSetPasswordRequest): Candidate OTP and desired new password.
            redis (aioredis.Redis): Redis client for OTP verification.

        Returns:
            dict: Success confirmation message.

        Raises:
            HTTPException: 400 if OTP is incorrect or expired.
        """
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
