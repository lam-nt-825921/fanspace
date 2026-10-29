"""Data Transfer Objects and Pydantic Schemas for Identity & Authentication.

This module defines strict validation rules, input request models, output serialization
schemas, and typed Swagger response models for all authentication endpoints.
"""

import uuid
from datetime import datetime
from pydantic import BaseModel, EmailStr, Field

from app.modules.identity.otp_service import OTPPurpose


class UserRegister(BaseModel):
    """Payload for standard email and password account registration."""
    email: EmailStr = Field(
        ...,
        description="Địa chỉ email cá nhân duy nhất của người dùng",
        examples=["fan_sky@example.com"],
    )
    username: str = Field(
        ...,
        min_length=3,
        max_length=50,
        pattern=r"^[a-zA-Z0-9_-]+$",
        description="Tên tài khoản duy nhất (chỉ gồm chữ cái, số, gạch dưới và gạch ngang)",
        examples=["sky_fan_99"],
    )
    password: str = Field(
        ...,
        min_length=6,
        max_length=100,
        description="Mật khẩu bảo mật cho tài khoản",
        examples=["SuperSecurePassword123!"],
    )
    display_name: str = Field(
        ...,
        min_length=1,
        max_length=100,
        description="Tên hiển thị công khai trên mạng xã hội",
        examples=["Sky Fandom 01"],
    )
    platform: str | None = Field(
        None,
        description="Nền tảng thiết bị đăng nhập ('MOBILE', 'DESKTOP', 'WEB')",
        examples=["WEB"],
    )
    device_id: str | None = Field(
        None,
        description="Mã định danh duy nhất của thiết bị (bắt buộc khi platform là 'MOBILE')",
        examples=["android_hardware_uuid_123"],
    )


class UserLogin(BaseModel):
    """Payload for standard password authentication."""
    email: EmailStr = Field(
        ...,
        description="Địa chỉ email đã đăng ký",
        examples=["fan_sky@example.com"],
    )
    password: str = Field(
        ...,
        description="Mật khẩu của tài khoản",
        examples=["SuperSecurePassword123!"],
    )
    platform: str | None = Field(
        None,
        description="Nền tảng ứng dụng đang đăng nhập ('MOBILE', 'DESKTOP', 'WEB')",
        examples=["MOBILE"],
    )
    device_id: str | None = Field(
        None,
        description="Mã định danh thiết bị (bắt buộc khi platform là 'MOBILE')",
        examples=["ios_uuid_456"],
    )


class GoogleLogin(BaseModel):
    """Payload for Google OAuth2 authentication (Mobile/Web)."""
    id_token: str = Field(
        ...,
        min_length=10,
        description="Google JWT ID Token thu được từ Google Sign-In SDK (bắt buộc xác thực chữ ký với Google)",
        examples=["eyJhbGciOiJSUzI1NiIs..."],
    )
    platform: str | None = Field(
        None,
        description="Nền tảng ứng dụng ('MOBILE', 'DESKTOP', 'WEB')",
        examples=["MOBILE"],
    )
    device_id: str | None = Field(
        None,
        description="Mã định danh thiết bị (bắt buộc khi platform là 'MOBILE')",
        examples=["android_device_id_789"],
    )


class Token(BaseModel):
    """Access and refresh tokens issued upon authentication."""
    access_token: str = Field(..., description="JWT Bearer token truy cập API có thời hạn 30 phút")
    refresh_token: str = Field(..., description="JWT Refresh token xoay vòng có thời hạn 7 ngày")
    token_type: str = Field(default="bearer", description="Loại token (luôn là 'bearer')")
    session_id: uuid.UUID | None = Field(None, description="Mã định danh phiên đăng nhập trên thiết bị")


class RefreshTokenRequest(BaseModel):
    """Payload for rotating tokens using an existing refresh token."""
    refresh_token: str = Field(..., description="Refresh token đang hoạt động")


class OAuthTicketExchangeRequest(BaseModel):
    """Payload to exchange a single-use short-lived OAuth ticket for authentication tokens."""
    ticket: str = Field(..., description="Mã vé tạm thời dùng 1 lần (TTL 60s) nhận được từ OAuth redirect callback")


class EmailSendOTPRequest(BaseModel):
    """Payload to request an OTP code via email."""
    email: EmailStr = Field(..., description="Email nhận mã xác thực", examples=["fan@example.com"])
    purpose: OTPPurpose = Field(
        default=OTPPurpose.VERIFY_EMAIL,
        description="Mục đích xác thực: VERIFY_EMAIL, OAUTH_SET_PASSWORD, RESET_PASSWORD, DELETE_ACCOUNT",
    )


class EmailVerifyOTPRequest(BaseModel):
    """Payload to verify an OTP code and activate an account."""
    email: EmailStr = Field(..., description="Email đã nhận mã OTP", examples=["fan@example.com"])
    code: str = Field(..., min_length=6, max_length=6, description="Mã OTP gồm 6 chữ số", examples=["839201"])
    purpose: OTPPurpose = Field(
        default=OTPPurpose.VERIFY_EMAIL,
        description="Mục đích xác thực",
    )


class OAuthSetPasswordRequest(BaseModel):
    """Payload to establish a password for a pure Google OAuth account."""
    otp: str = Field(..., min_length=6, max_length=6, description="Mã OTP gửi về Gmail của tài khoản", examples=["123456"])
    new_password: str = Field(..., min_length=6, max_length=100, description="Mật khẩu mới muốn thiết lập")


class DeleteAccountRequest(BaseModel):
    """Payload to confirm account soft deletion."""
    password: str | None = Field(
        None,
        description="Mật khẩu hiện tại (bắt buộc nếu tài khoản có mật khẩu)",
        examples=["MyCurrentPassword123!"],
    )
    otp: str | None = Field(
        None,
        description="Mã OTP gửi về email (bắt buộc nếu là tài khoản mạng xã hội chưa có mật khẩu)",
        examples=["654321"],
    )


class SessionOut(BaseModel):
    """Active device session metadata for user session inspection."""
    id: uuid.UUID = Field(..., description="Mã định danh phiên")
    platform: str = Field(..., description="Nền tảng đăng nhập: MOBILE, DESKTOP, WEB")
    device_id: str | None = Field(None, description="Mã thiết bị nếu là ứng dụng di động")
    device_name: str = Field(..., description="Tên thiết bị và hệ điều hành")
    ip_address: str | None = Field(None, description="Địa chỉ IP của thiết bị khi đăng nhập")
    is_active: bool = Field(..., description="Trạng thái phiên đang hoạt động hay đã bị đăng xuất")
    last_active_at: datetime = Field(..., description="Thời điểm tương tác hoặc refresh gần nhất")
    created_at: datetime = Field(..., description="Thời điểm khởi tạo phiên")
    is_current: bool = Field(default=False, description="Đánh dấu True nếu đây chính là thiết bị đang gọi API")

    model_config = {"from_attributes": True}


class UserOut(BaseModel):
    """Public user profile information."""
    id: uuid.UUID = Field(..., description="ID định danh duy nhất của người dùng")
    email: str = Field(..., description="Địa chỉ email cá nhân")
    username: str = Field(..., description="Tên định danh tài khoản")
    display_name: str = Field(..., description="Tên hiển thị công khai")
    avatar_url: str | None = Field(None, description="Đường dẫn ảnh đại diện")
    bio: str | None = Field(None, description="Tiểu sử tóm tắt")
    coin_balance: int = Field(default=0, description="Số dư xu trong ví (khởi tạo bằng 0)")
    is_email_verified: bool = Field(default=False, description="Trạng thái đã xác thực email hay chưa")
    system_role: str = Field(default="USER", description="Vai trò hệ thống: USER, SYSTEM_MODERATOR, SYSTEM_ADMIN")
    has_password: bool = Field(default=True, description="True nếu tài khoản đã thiết lập mật khẩu")
    is_google_linked: bool = Field(default=False, description="True nếu tài khoản đã liên kết với Google")
    created_at: datetime = Field(..., description="Thời điểm tham gia hệ thống")

    model_config = {"from_attributes": True}


class AuthResponse(BaseModel):
    """Standardized response schema for authentication and token generation."""
    success: bool = Field(default=True, description="Trạng thái thực thi")
    message: str | None = Field(default=None, description="Thông điệp phản hồi")
    tokens: Token = Field(..., description="Cặp mã token truy cập và refresh")
    user: UserOut = Field(..., description="Dữ liệu hồ sơ người dùng")


class RegisterInitResponse(BaseModel):
    """Response returned when a registration request is staged in Redis pending OTP verification."""
    success: bool = Field(default=True, description="Trạng thái ghi nhận yêu cầu đăng ký tạm thời")
    require_otp: bool = Field(default=True, description="Cờ bắt buộc xác thực OTP để chính thức tạo tài khoản")
    email: EmailStr = Field(..., description="Địa chỉ email nhận mã OTP xác thực")
    expires_in_seconds: int = Field(
        default=600,
        description="Thời gian tồn tại tối đa của yêu cầu đăng ký tạm trước khi tự hủy (giây)",
    )
    message: str = Field(..., description="Thông báo hướng dẫn người dùng nhập mã OTP")
    dev_otp: str | None = Field(
        None,
        description="Mã OTP hiển thị khi bật DEBUG phục vụ kiểm thử tự động",
    )


class OTPVerifyResponse(BaseModel):
    """Response returned after verifying an OTP code (includes tokens & user when completing registration)."""
    success: bool = Field(default=True, description="Trạng thái xác thực OTP")
    message: str = Field(..., description="Nội dung thông báo kết quả")
    tokens: Token | None = Field(
        None,
        description="Cặp JWT token cấp mới (chỉ có khi hoàn tất tạo tài khoản qua VERIFY_EMAIL)",
    )
    user: UserOut | None = Field(
        None,
        description="Thông tin tài khoản vừa được khởi tạo (chỉ có khi hoàn tất VERIFY_EMAIL)",
    )


class MessageResponse(BaseModel):
    """Generic message acknowledgment schema."""
    success: bool = Field(default=True, description="Trạng thái thành công")
    message: str = Field(..., description="Nội dung thông báo")


class OTPSendResponse(BaseModel):
    """Response returned upon requesting an OTP code."""
    success: bool = Field(default=True, description="Trạng thái gửi mã")
    message: str = Field(..., description="Thông báo xác nhận gửi thành công")
    dev_otp: str | None = Field(None, description="Mã OTP hiển thị khi bật DEBUG phục vụ kiểm thử")


class GoogleAuthUrlResponse(BaseModel):
    """Response containing the OAuth2 consent URL for Google login."""
    url: str = Field(..., description="Đường dẫn chuyển hướng tới trang cấp quyền của Google OAuth2")


class RevokeAllSessionsResponse(BaseModel):
    """Response confirming remote logout of all external device sessions."""
    success: bool = Field(default=True, description="Trạng thái thu hồi")
    message: str = Field(..., description="Thông báo kết quả")
    revoked_count: int = Field(..., description="Số lượng phiên đăng nhập khác đã bị thu hồi")


class UserUpdateProfile(BaseModel):
    """Payload for updating public profile information."""
    display_name: str | None = Field(None, min_length=1, max_length=100, description="Tên hiển thị mới")
    avatar_url: str | None = Field(None, max_length=500, description="URL ảnh đại diện mới")
    bio: str | None = Field(None, max_length=500, description="Tiểu sử tóm tắt")


class PasswordChangeRequest(BaseModel):
    """Payload for changing current account password."""
    old_password: str = Field(..., min_length=6, max_length=100, description="Mật khẩu hiện tại")
    new_password: str = Field(..., min_length=6, max_length=100, description="Mật khẩu mới muốn đổi")

