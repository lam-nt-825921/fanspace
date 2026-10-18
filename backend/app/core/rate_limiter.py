"""Rate Limiting and Anti-Brute-Force Security Module.

This module provides high-throughput rate limiting backed by Redis.
It enforces quotas on public registration endpoints (IP-based) and implements
exponential lockout on login attempts to defend against credential-stuffing
and brute-force attacks.
"""

import redis.asyncio as aioredis
from fastapi import HTTPException, status
from app.core.config import get_settings

settings = get_settings()


class RateLimiter:
    """Provides static utility methods for Redis-backed rate limiting."""

    @staticmethod
    async def check_register_limit(redis: aioredis.Redis, ip_address: str) -> None:
        """Enforces IP-based rate limiting on new account registrations.

        Tracks the registration count per IP in Redis with a rolling TTL.
        Rejects requests exceeding `settings.REGISTER_RATE_LIMIT_MAX` within
        `settings.REGISTER_RATE_LIMIT_WINDOW` seconds.

        Args:
            redis (aioredis.Redis): Active asynchronous Redis connection.
            ip_address (str): Client IP address being evaluated.

        Raises:
            HTTPException: 429 Too Many Requests if the registration limit is exceeded.
        """
        key = f"ratelimit:register:ip:{ip_address}"
        current = await redis.incr(key)
        if current == 1:
            await redis.expire(key, settings.REGISTER_RATE_LIMIT_WINDOW)
        if current > settings.REGISTER_RATE_LIMIT_MAX:
            ttl = await redis.ttl(key)
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=f"Địa chỉ IP của bạn đã đăng ký quá số lần cho phép ({settings.REGISTER_RATE_LIMIT_MAX} lần). Vui lòng thử lại sau {max(ttl, 1)} giây.",
            )

    @staticmethod
    async def check_login_lockout(redis: aioredis.Redis, email: str) -> None:
        """Verifies if a user account is under active security lockout.

        Queries the failed login attempt counter in Redis for the provided email.
        If the counter exceeds `settings.LOGIN_MAX_FAILED_ATTEMPTS`, authentication
        is blocked until the lockout cooldown period expires.

        Args:
            redis (aioredis.Redis): Active asynchronous Redis connection.
            email (str): Account email address attempting to authenticate.

        Raises:
            HTTPException: 429 Too Many Requests if account is locked due to repeated failures.
        """
        key = f"ratelimit:login:failed:{email.lower()}"
        failed_count_str = await redis.get(key)
        if failed_count_str:
            failed_count = int(failed_count_str)
            if failed_count >= settings.LOGIN_MAX_FAILED_ATTEMPTS:
                ttl = await redis.ttl(key)
                minutes = max(ttl // 60, 1)
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail=f"Tài khoản đã nhập sai mật khẩu quá {settings.LOGIN_MAX_FAILED_ATTEMPTS} lần liên tiếp và tạm thời bị khóa bảo vệ. Vui lòng thử lại sau {minutes} phút.",
                )

    @staticmethod
    async def record_login_failure(redis: aioredis.Redis, email: str) -> int:
        """Increments the failed login attempt counter for an account.

        Sets a lockout TTL on the first recorded failure.

        Args:
            redis (aioredis.Redis): Active asynchronous Redis connection.
            email (str): Account email address that failed authentication.

        Returns:
            int: The updated count of consecutive login failures.
        """
        key = f"ratelimit:login:failed:{email.lower()}"
        current = await redis.incr(key)
        if current == 1:
            await redis.expire(key, settings.LOGIN_LOCKOUT_SECONDS)
        return current

    @staticmethod
    async def clear_login_failure(redis: aioredis.Redis, email: str) -> None:
        """Resets the failed login counter upon a successful authentication.

        Args:
            redis (aioredis.Redis): Active asynchronous Redis connection.
            email (str): Account email address that successfully logged in.
        """
        key = f"ratelimit:login:failed:{email.lower()}"
        await redis.delete(key)
