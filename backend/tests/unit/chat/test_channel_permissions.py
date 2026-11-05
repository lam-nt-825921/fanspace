"""Tests for decoupled Channel CRUD operations using injected MockPermissionChecker."""

import uuid
import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import delete

from app.core.database import AsyncSessionLocal
from app.core.permissions import (
    MockPermissionChecker,
    Permission,
    get_permission_checker,
)
from app.core.security import create_access_token, get_password_hash
from app.main import app
from app.modules.chat.models import Channel
from app.modules.fandom.models import Fandom
from app.modules.identity.models import User


async def _cleanup_channel_test_data(
    user_ids: list[uuid.UUID],
    fandom_ids: list[uuid.UUID],
) -> None:
    """Removes test users, fandoms, and channels."""
    async with AsyncSessionLocal() as db:
        if fandom_ids:
            await db.execute(delete(Channel).where(Channel.fandom_id.in_(fandom_ids)))
            await db.execute(delete(Fandom).where(Fandom.id.in_(fandom_ids)))
        if user_ids:
            await db.execute(delete(User).where(User.id.in_(user_ids)))
        await db.commit()


@pytest.mark.asyncio
async def test_channel_crud_with_mock_permissions():
    """Verifies channel endpoints enforce PermissionSpec purely via IPermissionChecker."""
    suffix = uuid.uuid4().hex[:8]
    owner = User(
        username=f"ch_owner_{suffix}",
        email=f"ch_owner_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("Password123!"),
        display_name="Owner User",
        is_active=True,
    )
    regular_user = User(
        username=f"ch_user_{suffix}",
        email=f"ch_user_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("Password123!"),
        display_name="Regular User",
        is_active=True,
    )

    async with AsyncSessionLocal() as db:
        db.add_all([owner, regular_user])
        await db.flush()

        fandom = Fandom(
            name=f"Mock Perm Fandom {suffix}",
            slug=f"mock-perm-fandom-{suffix}",
            description="Fandom kiểm thử mock permission",
            category="Âm nhạc",
            admission_mode="OPEN",
            is_public=True,
            member_count=1,
            owner_id=owner.id,
        )
        db.add(fandom)
        await db.commit()

        owner_id = owner.id
        regular_id = regular_user.id
        fandom_id = fandom.id
        slug = fandom.slug

    try:
        user_token = create_access_token(data={"sub": str(regular_id)})

        # 1. Mock grants VIEW_CHANNEL & READ_MESSAGES only -> GET succeeds, POST returns 403.
        app.dependency_overrides[get_permission_checker] = lambda: MockPermissionChecker(
            granted={Permission.VIEW_CHANNEL, Permission.READ_MESSAGES}
        )
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            list_res = await ac.get(
                f"/api/v1/fandoms/{slug}/channels",
                headers={"Authorization": f"Bearer {user_token}"},
            )
            assert list_res.status_code == 200, list_res.text
            assert len(list_res.json()["channels"]) == 3

            create_denied = await ac.post(
                f"/api/v1/fandoms/{slug}/channels",
                headers={"Authorization": f"Bearer {user_token}"},
                json={
                    "name": "goc-fanart",
                    "type": "TEXT",
                    "topic": "Kênh chia sẻ tranh vẽ",
                },
            )
            assert create_denied.status_code == 403

        # 2. Mock grants MANAGE_CHANNELS -> POST, PUT, DELETE succeed without DB role assignment.
        app.dependency_overrides[get_permission_checker] = lambda: MockPermissionChecker(
            granted={
                Permission.VIEW_CHANNEL,
                Permission.READ_MESSAGES,
                Permission.MANAGE_CHANNELS,
            }
        )
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            create_ok = await ac.post(
                f"/api/v1/fandoms/{slug}/channels",
                headers={"Authorization": f"Bearer {user_token}"},
                json={
                    "name": "goc-fanart",
                    "type": "TEXT",
                    "topic": "Kênh chia sẻ tranh vẽ",
                    "slow_mode_seconds": 10,
                },
            )
            assert create_ok.status_code == 201, create_ok.text
            created_channel = create_ok.json()
            assert created_channel["name"] == "goc-fanart"
            assert created_channel["slow_mode_seconds"] == 10
            channel_id = created_channel["id"]

            update_ok = await ac.put(
                f"/api/v1/fandoms/{slug}/channels/{channel_id}",
                headers={"Authorization": f"Bearer {user_token}"},
                json={
                    "name": "goc-sang-tao",
                    "topic": "Chủ đề mới đã cập nhật",
                    "slow_mode_seconds": 30,
                },
            )
            assert update_ok.status_code == 200, update_ok.text
            assert update_ok.json()["name"] == "goc-sang-tao"
            assert update_ok.json()["slow_mode_seconds"] == 30

            del_ok = await ac.delete(
                f"/api/v1/fandoms/{slug}/channels/{channel_id}",
                headers={"Authorization": f"Bearer {user_token}"},
            )
            assert del_ok.status_code == 200, del_ok.text
            assert del_ok.json()["success"] is True
    finally:
        app.dependency_overrides.pop(get_permission_checker, None)
        await _cleanup_channel_test_data([owner_id, regular_id], [fandom_id])
