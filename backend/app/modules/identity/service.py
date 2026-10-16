import uuid
from fastapi import HTTPException, status, Depends
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.database import get_db
from app.core.security import (
    get_password_hash,
    verify_password,
    create_access_token,
    create_refresh_token,
    decode_token,
)
from app.modules.identity.models import User
from app.modules.billing.models import Wallet
from app.modules.identity.schemas import (
    UserRegister,
    UserLogin,
    GoogleLogin,
    DevLogin,
    Token,
)

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")


class IdentityService:
    @staticmethod
    async def register(db: AsyncSession, data: UserRegister) -> tuple[User, Token]:
        # Check existing email or username
        query = select(User).where((User.email == data.email) | (User.username == data.username))
        result = await db.execute(query)
        if result.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email hoặc Tên tài khoản (username) đã được sử dụng.",
            )

        # Hash password & create user
        hashed_pwd = get_password_hash(data.password)
        user = User(
            email=data.email,
            username=data.username,
            password_hash=hashed_pwd,
            display_name=data.display_name,
        )
        db.add(user)
        await db.flush()

        # Create user wallet with welcome bonus 500 coins for testing
        wallet = Wallet(user_id=user.id, coin_balance=500)
        db.add(wallet)
        await db.commit()
        await db.refresh(user, ["wallet"])

        tokens = Token(
            access_token=create_access_token({"sub": str(user.id), "username": user.username}),
            refresh_token=create_refresh_token({"sub": str(user.id)}),
        )
        return user, tokens

    @staticmethod
    async def login(db: AsyncSession, data: UserLogin) -> tuple[User, Token]:
        query = select(User).where(User.email == data.email).options(selectinload(User.wallet))
        result = await db.execute(query)
        user = result.scalar_one_or_none()

        if not user or not user.password_hash or not verify_password(data.password, user.password_hash):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Email hoặc mật khẩu không chính xác.",
            )

        tokens = Token(
            access_token=create_access_token({"sub": str(user.id), "username": user.username}),
            refresh_token=create_refresh_token({"sub": str(user.id)}),
        )
        return user, tokens

    @staticmethod
    async def google_login(db: AsyncSession, data: GoogleLogin) -> tuple[User, Token]:
        query = select(User).where(User.email == data.email).options(selectinload(User.wallet))
        result = await db.execute(query)
        user = result.scalar_one_or_none()

        if not user:
            # Generate unique username from email
            base_username = data.email.split("@")[0][:40]
            username = f"{base_username}_{uuid.uuid4().hex[:6]}"
            user = User(
                email=data.email,
                username=username,
                display_name=data.display_name,
                avatar_url=data.avatar_url,
                is_email_verified=True,
            )
            db.add(user)
            await db.flush()

            wallet = Wallet(user_id=user.id, coin_balance=500)
            db.add(wallet)
            await db.commit()
            await db.refresh(user, ["wallet"])

        tokens = Token(
            access_token=create_access_token({"sub": str(user.id), "username": user.username}),
            refresh_token=create_refresh_token({"sub": str(user.id)}),
        )
        return user, tokens

    @staticmethod
    async def dev_login(db: AsyncSession, data: DevLogin) -> tuple[User, Token]:
        """Bypass authentication for automated scientific load tests (k6/Locust) and quick local dev"""
        query = select(User).where(User.username == data.username).options(selectinload(User.wallet))
        result = await db.execute(query)
        user = result.scalar_one_or_none()

        if not user:
            user = User(
                email=f"{data.username}@fanspace.local",
                username=data.username,
                display_name=f"Dev Fan {data.username}",
                is_email_verified=True,
            )
            db.add(user)
            await db.flush()

            wallet = Wallet(user_id=user.id, coin_balance=10000)
            db.add(wallet)
            await db.commit()
            await db.refresh(user, ["wallet"])

        tokens = Token(
            access_token=create_access_token({"sub": str(user.id), "username": user.username}),
            refresh_token=create_refresh_token({"sub": str(user.id)}),
        )
        return user, tokens


async def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: AsyncSession = Depends(get_db),
) -> User:
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
    except Exception:
        raise credentials_exception

    query = select(User).where(User.id == user_id).options(selectinload(User.wallet))
    result = await db.execute(query)
    user = result.scalar_one_or_none()
    if user is None:
        raise credentials_exception
    return user
