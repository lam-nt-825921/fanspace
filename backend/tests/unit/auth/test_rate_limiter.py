"""Unit tests for device-scoped registration rate limiting on shared Wi-Fi networks."""

import uuid

import pytest

from app.core.rate_limiter import RateLimiter
from app.core.redis import get_redis_client


@pytest.mark.asyncio
async def test_shared_wifi_distinct_devices_are_not_blocked_by_register_rate_limit() -> None:
    """Verifies that multiple distinct devices sharing one public Wi-Fi IP do not block each other."""
    redis = get_redis_client()
    shared_wifi_ip = f"203.113.10.{uuid.uuid4().int % 200 + 1}"

    # Simulate 8 distinct devices on the same Wi-Fi (exceeding REGISTER_RATE_LIMIT_MAX = 5 per single device)
    for idx in range(8):
        device_fingerprint = f"device-{idx}-{uuid.uuid4().hex[:6]}"
        await RateLimiter.check_register_limit(
            redis,
            shared_wifi_ip,
            client_fingerprint=device_fingerprint,
        )
