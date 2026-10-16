import uuid
from datetime import datetime
from pydantic import BaseModel, EmailStr, Field


class UserRegister(BaseModel):
    email: EmailStr
    username: str = Field(min_length=3, max_length=50, pattern=r"^[a-zA-Z0-9_-]+$")
    password: str = Field(min_length=6, max_length=100)
    display_name: str = Field(min_length=1, max_length=100)


class UserLogin(BaseModel):
    email: EmailStr
    password: str


class GoogleLogin(BaseModel):
    id_token: str | None = None
    email: EmailStr
    display_name: str
    avatar_url: str | None = None


class DevLogin(BaseModel):
    username: str = Field(default="dev_fan", min_length=3, max_length=50)


class Token(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class UserOut(BaseModel):
    id: uuid.UUID
    email: str
    username: str
    display_name: str
    avatar_url: str | None = None
    bio: str | None = None
    coin_balance: int = 0
    created_at: datetime

    model_config = {"from_attributes": True}
