"""Redis Connection Pool and Client Lifecycle Management.

This module provides an asynchronous Redis client instance configured with connection
pooling. It implements a transparent proxy and lifecycle hooks (`reset_redis_client`)
to maintain clean connection state across event loops in production and automated test suites.
"""

import redis.asyncio as aioredis
from app.core.config import get_settings

settings = get_settings()

_redis_client: aioredis.Redis | None = None


def get_redis_client() -> aioredis.Redis:
    """Retrieves or initializes the global asynchronous Redis client.

    Returns:
        aioredis.Redis: Active Redis client instance connected to `settings.REDIS_URL`.
    """
    global _redis_client
    if _redis_client is None:
        _redis_client = aioredis.from_url(
            settings.REDIS_URL,
            decode_responses=True,
            max_connections=50,
        )
    return _redis_client


class RedisProxy:
    """Transparent proxy delegating calls to the active Redis client instance.

    Guarantees that the underlying connection pool remains bound to the active
    running asyncio event loop.
    """

    def __getattr__(self, name: str):
        """Delegates attribute access to the underlying Redis client."""
        client = get_redis_client()
        return getattr(client, name)


redis_client = RedisProxy()


async def get_redis() -> aioredis.Redis:
    """FastAPI dependency for injecting the active asynchronous Redis client.

    Yields:
        aioredis.Redis: Injected Redis client instance.
    """
    return get_redis_client()


async def reset_redis_client() -> None:
    """Gracefully closes and resets the global Redis connection pool.

    Crucial for pytest fixtures to prevent 'Event loop is closed' exceptions
    when loop scopes transition between test cases.
    """
    global _redis_client
    if _redis_client is not None:
        try:
            await _redis_client.aclose()
        except Exception:
            pass
        _redis_client = None
