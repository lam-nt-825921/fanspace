from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.modules.identity.models import User
from app.modules.identity.schemas import (
    UserRegister,
    UserLogin,
    GoogleLogin,
    DevLogin,
    Token,
    UserOut,
)
from app.modules.identity.service import IdentityService, get_current_user

auth_router = APIRouter(prefix="/api/v1/auth", tags=["Authentication & Identity"])
users_router = APIRouter(prefix="/api/v1/users", tags=["Users"])


@auth_router.post("/register", response_model=dict, status_code=status.HTTP_201_CREATED)
async def register(data: UserRegister, db: AsyncSession = Depends(get_db)):
    user, tokens = await IdentityService.register(db, data)
    return {
        "success": True,
        "message": "Đăng ký tài khoản thành công.",
        "tokens": tokens,
        "user": UserOut(
            id=user.id,
            email=user.email,
            username=user.username,
            display_name=user.display_name,
            avatar_url=user.avatar_url,
            bio=user.bio,
            coin_balance=user.wallet.coin_balance if user.wallet else 0,
            created_at=user.created_at,
        ),
    }


@auth_router.post("/login", response_model=dict)
async def login(data: UserLogin, db: AsyncSession = Depends(get_db)):
    user, tokens = await IdentityService.login(db, data)
    return {
        "success": True,
        "tokens": tokens,
        "user": UserOut(
            id=user.id,
            email=user.email,
            username=user.username,
            display_name=user.display_name,
            avatar_url=user.avatar_url,
            bio=user.bio,
            coin_balance=user.wallet.coin_balance if user.wallet else 0,
            created_at=user.created_at,
        ),
    }


@auth_router.post("/google", response_model=dict)
async def google_login(data: GoogleLogin, db: AsyncSession = Depends(get_db)):
    user, tokens = await IdentityService.google_login(db, data)
    return {
        "success": True,
        "tokens": tokens,
        "user": UserOut(
            id=user.id,
            email=user.email,
            username=user.username,
            display_name=user.display_name,
            avatar_url=user.avatar_url,
            bio=user.bio,
            coin_balance=user.wallet.coin_balance if user.wallet else 0,
            created_at=user.created_at,
        ),
    }


@auth_router.post("/dev-login", response_model=dict)
async def dev_login(data: DevLogin, db: AsyncSession = Depends(get_db)):
    user, tokens = await IdentityService.dev_login(db, data)
    return {
        "success": True,
        "tokens": tokens,
        "user": UserOut(
            id=user.id,
            email=user.email,
            username=user.username,
            display_name=user.display_name,
            avatar_url=user.avatar_url,
            bio=user.bio,
            coin_balance=user.wallet.coin_balance if user.wallet else 0,
            created_at=user.created_at,
        ),
    }


@users_router.get("/me", response_model=UserOut)
async def get_me(current_user: User = Depends(get_current_user)):
    return UserOut(
        id=current_user.id,
        email=current_user.email,
        username=current_user.username,
        display_name=current_user.display_name,
        avatar_url=current_user.avatar_url,
        bio=current_user.bio,
        coin_balance=current_user.wallet.coin_balance if current_user.wallet else 0,
        created_at=current_user.created_at,
    )
