import redis.asyncio as aioredis
from app.core.config import get_settings

settings = get_settings()

_redis_client: aioredis.Redis | None = None


def get_redis_client() -> aioredis.Redis:
    global _redis_client
    if _redis_client is None:
        _redis_client = aioredis.from_url(
            settings.REDIS_URL,
            decode_responses=True,
            max_connections=50,
        )
    return _redis_client


class RedisProxy:
    """Proxy object allowing module-level redis_client usage while ensuring proper event loop lifecycle"""
    def __getattr__(self, name):
        client = get_redis_client()
        return getattr(client, name)


redis_client = RedisProxy()


async def get_redis() -> aioredis.Redis:
    return get_redis_client()


async def reset_redis_client():
    global _redis_client
    if _redis_client is not None:
        try:
            await _redis_client.aclose()
        except Exception:
            pass
        _redis_client = None
