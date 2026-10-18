import redis.asyncio as aioredis
from fastapi import HTTPException, status
from app.core.config import get_settings

settings = get_settings()


class RateLimiter:
    @staticmethod
    async def check_register_limit(redis: aioredis.Redis, ip_address: str):
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
    async def check_login_lockout(redis: aioredis.Redis, email: str):
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
        key = f"ratelimit:login:failed:{email.lower()}"
        current = await redis.incr(key)
        if current == 1:
            await redis.expire(key, settings.LOGIN_LOCKOUT_SECONDS)
        return current

    @staticmethod
    async def clear_login_failure(redis: aioredis.Redis, email: str):
        key = f"ratelimit:login:failed:{email.lower()}"
        await redis.delete(key)
