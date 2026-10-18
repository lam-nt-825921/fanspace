import uuid
from datetime import datetime
from pydantic import BaseModel, EmailStr, Field

from app.modules.identity.otp_service import OTPPurpose


class UserRegister(BaseModel):
    email: EmailStr
    username: str = Field(min_length=3, max_length=50, pattern=r"^[a-zA-Z0-9_-]+$")
    password: str = Field(min_length=6, max_length=100)
    display_name: str = Field(min_length=1, max_length=100)
    platform: str | None = None  # "MOBILE", "DESKTOP", "WEB"
    device_id: str | None = None  # Required when platform is MOBILE


class UserLogin(BaseModel):
    email: EmailStr
    password: str
    platform: str | None = None
    device_id: str | None = None


class GoogleLogin(BaseModel):
    id_token: str | None = None
    email: EmailStr | None = None
    display_name: str | None = None
    avatar_url: str | None = None
    platform: str | None = None
    device_id: str | None = None


class DevLogin(BaseModel):
    username: str = Field(default="dev_fan", min_length=3, max_length=50)
    platform: str | None = None
    device_id: str | None = None


class Token(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    session_id: uuid.UUID | None = None


class RefreshTokenRequest(BaseModel):
    refresh_token: str


class EmailSendOTPRequest(BaseModel):
    email: EmailStr
    purpose: OTPPurpose = OTPPurpose.VERIFY_EMAIL


class EmailVerifyOTPRequest(BaseModel):
    email: EmailStr
    code: str = Field(min_length=6, max_length=6)
    purpose: OTPPurpose = OTPPurpose.VERIFY_EMAIL


class OAuthSetPasswordRequest(BaseModel):
    otp: str = Field(min_length=6, max_length=6)
    new_password: str = Field(min_length=6, max_length=100)


class DeleteAccountRequest(BaseModel):
    password: str | None = None
    otp: str | None = None


class SessionOut(BaseModel):
    id: uuid.UUID
    platform: str
    device_id: str | None = None
    device_name: str
    ip_address: str | None = None
    is_active: bool
    last_active_at: datetime
    created_at: datetime
    is_current: bool = False

    model_config = {"from_attributes": True}


class UserOut(BaseModel):
    id: uuid.UUID
    email: str
    username: str
    display_name: str
    avatar_url: str | None = None
    bio: str | None = None
    coin_balance: int = 0
    is_email_verified: bool = False
    system_role: str = "USER"
    has_password: bool = True
    is_google_linked: bool = False
    created_at: datetime

    model_config = {"from_attributes": True}
