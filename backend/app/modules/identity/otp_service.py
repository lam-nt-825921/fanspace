"""One-Time Password (OTP) Generation, Verification, and Lifecycle Management.

This module manages the lifecycle of 6-digit numeric OTP verification codes using Redis.
It implements rate-limiting cooldowns, brute-force attack counters, single-use invalidation,
and background dispatch of verification emails.
"""

import enum
import json
import secrets
import redis.asyncio as aioredis
from fastapi import BackgroundTasks, HTTPException, status

from app.core.config import get_settings
from app.core.mailer import send_otp_email

settings = get_settings()


class OTPPurpose(str, enum.Enum):
    """Enumeration of recognized security purposes for OTP generation.

    Attributes:
        VERIFY_EMAIL: Account activation following standard registration.
        OAUTH_SET_PASSWORD: Identity verification before setting a password for an OAuth account.
        RESET_PASSWORD: Password recovery for forgotten credentials.
        DELETE_ACCOUNT: Re-authentication before executing account soft deletion.
    """
    VERIFY_EMAIL = "VERIFY_EMAIL"
    OAUTH_SET_PASSWORD = "OAUTH_SET_PASSWORD"
    RESET_PASSWORD = "RESET_PASSWORD"
    DELETE_ACCOUNT = "DELETE_ACCOUNT"


PURPOSE_LABELS: dict[OTPPurpose, str] = {
    OTPPurpose.VERIFY_EMAIL: "Kích hoạt tài khoản FanSpace",
    OTPPurpose.OAUTH_SET_PASSWORD: "Cấp mật khẩu tài khoản FanSpace",
    OTPPurpose.RESET_PASSWORD: "Đặt lại mật khẩu FanSpace",
    OTPPurpose.DELETE_ACCOUNT: "Xác nhận xóa tài khoản FanSpace",
}


class OTPService:
    """Service providing static utilities for OTP generation, rate limiting, and verification."""

    @staticmethod
    def generate_otp() -> str:
        """Generates a cryptographically secure 6-digit numeric OTP.

        Returns:
            str: 6-character string representing digits between 100000 and 999999.
        """
        return f"{secrets.randbelow(900000) + 100000}"

    @classmethod
    async def send_otp(
        cls,
        redis: aioredis.Redis,
        email: str,
        purpose: OTPPurpose,
        background_tasks: BackgroundTasks,
    ) -> str:
        """Generates, stores, and enqueues an OTP verification email.

        Enforces a 60-second cooldown per email and a maximum quota of 5 requests
        per hour. Persists the code in Redis with a 5-minute time-to-live (TTL).

        Args:
            redis (aioredis.Redis): Active asynchronous Redis connection.
            email (str): Target recipient email address.
            purpose (OTPPurpose): The functional operation requiring verification.
            background_tasks (BackgroundTasks): FastAPI background task manager to dispatch email.

        Returns:
            str: The generated 6-digit OTP code.

        Raises:
            HTTPException: 429 Too Many Requests if the 60-second cooldown is active
                or hourly quota is exceeded.
        """
        clean_email = email.strip().lower()
        cooldown_key = f"ratelimit:otp:cooldown:{purpose.value}:{clean_email}"

        # 1. Check cooldown (60s)
        if await redis.exists(cooldown_key):
            ttl = await redis.ttl(cooldown_key)
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=f"Vui lòng đợi {max(ttl, 1)} giây trước khi yêu cầu mã OTP mới.",
            )

        # 2. Check hourly limit (5 per hour)
        hourly_key = f"ratelimit:otp:hourly:{purpose.value}:{clean_email}"
        hourly_count = await redis.incr(hourly_key)
        if hourly_count == 1:
            await redis.expire(hourly_key, 3600)
        if hourly_count > 5:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Bạn đã yêu cầu mã OTP quá 5 lần trong vòng 1 giờ. Vui lòng thử lại sau.",
            )

        # 3. Generate code & set in Redis (5 min TTL)
        code = cls.generate_otp()
        otp_key = f"otp:{purpose.value}:{clean_email}"
        payload = {"code": code, "attempts": 0}

        await redis.set(otp_key, json.dumps(payload), ex=settings.OTP_TTL_SECONDS)
        await redis.set(cooldown_key, "1", ex=settings.OTP_COOLDOWN_SECONDS)

        # 4. Enqueue email sending in background
        label = PURPOSE_LABELS.get(purpose, "Xác thực")
        background_tasks.add_task(send_otp_email, clean_email, code, label)

        return code

    @classmethod
    async def verify_otp(
        cls,
        redis: aioredis.Redis,
        email: str,
        code: str,
        purpose: OTPPurpose,
    ) -> bool:
        """Validates a candidate OTP code against Redis storage.

        Implements single-use consumption upon match and increments the failure counter
        on mismatch. Revokes the code completely if failed attempts reach `settings.OTP_MAX_ATTEMPTS`.

        Args:
            redis (aioredis.Redis): Active asynchronous Redis connection.
            email (str): Target email address associated with the code.
            code (str): Candidate 6-digit OTP code submitted by the user.
            purpose (OTPPurpose): The functional operation being verified.

        Returns:
            bool: True if the code matches and was successfully consumed.

        Raises:
            HTTPException: 400 Bad Request if the code does not exist, has expired,
                has exceeded maximum retry attempts, or is incorrect.
        """
        clean_email = email.strip().lower()
        otp_key = f"otp:{purpose.value}:{clean_email}"

        raw = await redis.get(otp_key)
        if not raw:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Mã OTP không tồn tại hoặc đã hết hạn (quá 5 phút). Vui lòng yêu cầu mã mới.",
            )

        try:
            data = json.loads(raw)
        except Exception:
            await redis.delete(otp_key)
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Dữ liệu mã OTP không hợp lệ.",
            )

        attempts = data.get("attempts", 0)

        # Check brute force limit
        if attempts >= settings.OTP_MAX_ATTEMPTS:
            await redis.delete(otp_key)
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Bạn đã nhập sai mã OTP quá {settings.OTP_MAX_ATTEMPTS} lần. Mã đã bị hủy để bảo vệ an toàn. Vui lòng yêu cầu mã mới.",
            )

        if data.get("code") != code.strip():
            data["attempts"] = attempts + 1
            remaining_ttl = await redis.ttl(otp_key)
            if remaining_ttl > 0:
                await redis.set(otp_key, json.dumps(data), ex=remaining_ttl)
            remaining_attempts = max(settings.OTP_MAX_ATTEMPTS - data["attempts"], 0)
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Mã OTP không chính xác. Bạn còn {remaining_attempts} lần thử.",
            )

        # Successfully verified: delete key immediately (Single-use)
        await redis.delete(otp_key)
        return True
