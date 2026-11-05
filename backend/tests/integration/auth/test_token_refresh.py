"""Integration tests for refresh token rotation and concurrent grace period handling."""

import uuid
from datetime import datetime, timedelta, timezone

import pytest

from app.core.client_detector import ClientInfo
from app.core.database import AsyncSessionLocal, init_db
from app.core.redis import get_redis_client
from app.core.security import create_refresh_token, get_password_hash, hash_token
from app.modules.identity.models import SystemRole, User, UserSession
from app.modules.identity.service import IdentityService


@pytest.mark.asyncio
async def test_concurrent_refresh_token_within_grace_period_preserves_session() -> None:
    """Verifies that a concurrent refresh request with the just-rotated token does not revoke the session."""
    await init_db()
    redis = get_redis_client()

    suffix = uuid.uuid4().hex[:8]
    user_id = uuid.uuid4()
    session_id = uuid.uuid4()
    initial_refresh = create_refresh_token(
        {"sub": str(user_id), "session_id": str(session_id)}
    )

    async with AsyncSessionLocal() as db:
        user = User(
            id=user_id,
            email=f"grace_{suffix}@fanspace.vn",
            username=f"grace_{suffix}",
            password_hash=get_password_hash("Fanspace@2026"),
            display_name="Grace Tester",
            system_role=SystemRole.USER.value,
            is_email_verified=True,
            is_active=True,
        )
        db.add(user)
        await db.flush()

        session = UserSession(
            id=session_id,
            user_id=user_id,
            platform="WEB",
            device_id=f"web-{suffix}",
            device_name="Chrome Linux",
            ip_address="127.0.0.1",
            user_agent="Mozilla/5.0",
            refresh_token_hash=hash_token(initial_refresh),
            is_active=True,
            expires_at=datetime.now(timezone.utc) + timedelta(days=7),
        )
        db.add(session)
        await db.commit()

        client_info = ClientInfo(
            platform="WEB",
            device_id=f"web-{suffix}",
            device_name="Chrome Linux",
            ip_address="127.0.0.1",
            user_agent="Mozilla/5.0",
        )

        # First refresh rotates the token
        first_bundle = await IdentityService.refresh_token(
            db, initial_refresh, client_info, redis=redis
        )
        assert first_bundle.access_token
        assert first_bundle.refresh_token != initial_refresh

        # Second concurrent request arrives immediately with the same `initial_refresh` token
        second_bundle = await IdentityService.refresh_token(
            db, initial_refresh, client_info, redis=redis
        )
        assert second_bundle.access_token == first_bundle.access_token
        assert second_bundle.refresh_token == first_bundle.refresh_token

        # Verify the session remains active in PostgreSQL
        await db.refresh(session)
        assert session.is_active is True
