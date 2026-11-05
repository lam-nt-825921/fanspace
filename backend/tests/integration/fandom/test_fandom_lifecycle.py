"""Integration tests for Fandom Lifecycle Management (FR-06 / UC-05).

Covers:
1. Fandom Ownership Quota (enforcing MAX_FANDOMS_PER_OWNER = 5).
2. Toggling Public / Private visibility mode (PATCH /api/v1/fandoms/{identifier}/visibility).
3. Secure deletion of Fandom with password verification and cascade cleanup (DELETE /api/v1/fandoms/{identifier}).
"""

import uuid
import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import delete, select

from app.core.database import AsyncSessionLocal
from app.core.security import create_access_token, get_password_hash
from app.main import app
from app.modules.chat.models import Channel
from app.modules.fandom.models import Fandom, FandomMember
from app.modules.identity.models import User
from app.modules.rbac.models import MemberRole, Role


async def _cleanup_entities(user_ids: list[uuid.UUID], fandom_ids: list[uuid.UUID]) -> None:
    """Cleans up database records created during test runs."""
    async with AsyncSessionLocal() as db:
        if fandom_ids:
            await db.execute(delete(Channel).where(Channel.fandom_id.in_(fandom_ids)))
            await db.execute(delete(MemberRole).where(MemberRole.fandom_id.in_(fandom_ids)))
            await db.execute(delete(Role).where(Role.fandom_id.in_(fandom_ids)))
            await db.execute(delete(FandomMember).where(FandomMember.fandom_id.in_(fandom_ids)))
            await db.execute(delete(Fandom).where(Fandom.id.in_(fandom_ids)))
        if user_ids:
            await db.execute(delete(User).where(User.id.in_(user_ids)))
        await db.commit()


@pytest.mark.asyncio
async def test_fandom_creation_quota_limit():
    """Verifies that an owner cannot exceed the limit of 5 owned fandoms."""
    suffix = uuid.uuid4().hex[:8]
    password = "SecurePassword123!"
    owner = User(
        username=f"quota_user_{suffix}",
        email=f"quota_user_{suffix}@test.vn",
        password_hash=get_password_hash(password),
        display_name="Quota Tester",
        is_active=True,
    )
    async with AsyncSessionLocal() as db:
        db.add(owner)
        await db.commit()
        await db.refresh(owner)

    token = create_access_token(data={"sub": str(owner.id), "username": owner.username})
    headers = {"Authorization": f"Bearer {token}"}
    transport = ASGITransport(app=app)
    created_fandom_ids: list[uuid.UUID] = []

    try:
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            # 1. Successfully create 5 fandoms
            for i in range(1, 6):
                slug = f"fandom-quota-{suffix}-{i}"
                res = await client.post(
                    "/api/v1/fandoms",
                    headers=headers,
                    json={
                        "name": f"Quota Fandom {i}",
                        "slug": slug,
                        "category": "Âm nhạc",
                        "admission_mode": "OPEN",
                    },
                )
                assert res.status_code == 201, f"Failed at {i}: {res.text}"
                data = res.json()
                created_fandom_ids.append(uuid.UUID(data["fandom_id"]))

            # 2. Check my fandoms endpoint reflects quota
            my_res = await client.get("/api/v1/fandoms/me/fandoms", headers=headers)
            assert my_res.status_code == 200
            my_data = my_res.json()
            assert my_data["quota_used"] == 5
            assert my_data["max_quota"] == 5

            # 3. Attempt to create the 6th fandom - must fail with 400 Bad Request
            res_exceeded = await client.post(
                "/api/v1/fandoms",
                headers=headers,
                json={
                    "name": f"Quota Fandom 6",
                    "slug": f"fandom-quota-{suffix}-6",
                    "category": "Âm nhạc",
                    "admission_mode": "OPEN",
                },
            )
            assert res_exceeded.status_code == 400
            assert "giới hạn tối đa 5 Fandom" in res_exceeded.json()["detail"]
    finally:
        await _cleanup_entities([owner.id], created_fandom_ids)


@pytest.mark.asyncio
async def test_update_fandom_visibility():
    """Verifies owner can toggle public/private visibility and non-owner cannot."""
    suffix = uuid.uuid4().hex[:8]
    password = "SecurePassword123!"
    owner = User(
        username=f"vis_owner_{suffix}",
        email=f"vis_owner_{suffix}@test.vn",
        password_hash=get_password_hash(password),
        display_name="Visibility Owner",
        is_active=True,
    )
    other_user = User(
        username=f"vis_other_{suffix}",
        email=f"vis_other_{suffix}@test.vn",
        password_hash=get_password_hash(password),
        display_name="Other User",
        is_active=True,
    )
    async with AsyncSessionLocal() as db:
        db.add_all([owner, other_user])
        await db.commit()
        await db.refresh(owner)
        await db.refresh(other_user)

    owner_token = create_access_token(data={"sub": str(owner.id), "username": owner.username})
    other_token = create_access_token(data={"sub": str(other_user.id), "username": other_user.username})

    owner_headers = {"Authorization": f"Bearer {owner_token}"}
    other_headers = {"Authorization": f"Bearer {other_token}"}
    transport = ASGITransport(app=app)
    fandom_id = None

    try:
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            # 1. Create public fandom
            slug = f"vis-fandom-{suffix}"
            create_res = await client.post(
                "/api/v1/fandoms",
                headers=owner_headers,
                json={
                    "name": "Visibility Space",
                    "slug": slug,
                    "category": "Công nghệ",
                    "is_public": True,
                },
            )
            assert create_res.status_code == 201
            fandom_id = uuid.UUID(create_res.json()["fandom_id"])

            # 2. Non-owner cannot change visibility -> 403 Forbidden
            forbidden_res = await client.patch(
                f"/api/v1/fandoms/{slug}/visibility",
                headers=other_headers,
                json={"is_public": False},
            )
            assert forbidden_res.status_code == 403

            # 3. Owner changes visibility to private (False)
            patch_res = await client.patch(
                f"/api/v1/fandoms/{slug}/visibility",
                headers=owner_headers,
                json={"is_public": False},
            )
            assert patch_res.status_code == 200
            assert patch_res.json()["is_public"] is False

            # 4. Other user viewing private fandom preview gets 404
            preview_res = await client.get(
                f"/api/v1/fandoms/{slug}/preview",
                headers=other_headers,
            )
            assert preview_res.status_code == 404

            # 5. Owner viewing private fandom preview succeeds
            owner_preview_res = await client.get(
                f"/api/v1/fandoms/{slug}/preview",
                headers=owner_headers,
            )
            assert owner_preview_res.status_code == 200
            assert owner_preview_res.json()["is_public"] is False

            # 6. Owner switches back to public
            patch_back_res = await client.patch(
                f"/api/v1/fandoms/{slug}/visibility",
                headers=owner_headers,
                json={"is_public": True},
            )
            assert patch_back_res.status_code == 200
            assert patch_back_res.json()["is_public"] is True

            # 7. Other user can view preview now
            preview_public_res = await client.get(
                f"/api/v1/fandoms/{slug}/preview",
                headers=other_headers,
            )
            assert preview_public_res.status_code == 200
    finally:
        await _cleanup_entities([owner.id, other_user.id], [fandom_id] if fandom_id else [])


@pytest.mark.asyncio
async def test_delete_fandom_lifecycle_and_cascade():
    """Verifies secure deletion of fandom with password confirmation and full cascade."""
    suffix = uuid.uuid4().hex[:8]
    password = "CorrectPassword123!"
    owner = User(
        username=f"del_owner_{suffix}",
        email=f"del_owner_{suffix}@test.vn",
        password_hash=get_password_hash(password),
        display_name="Deletion Owner",
        is_active=True,
    )
    other_user = User(
        username=f"del_other_{suffix}",
        email=f"del_other_{suffix}@test.vn",
        password_hash=get_password_hash(password),
        display_name="Other User",
        is_active=True,
    )
    async with AsyncSessionLocal() as db:
        db.add_all([owner, other_user])
        await db.commit()
        await db.refresh(owner)
        await db.refresh(other_user)

    owner_token = create_access_token(data={"sub": str(owner.id), "username": owner.username})
    other_token = create_access_token(data={"sub": str(other_user.id), "username": other_user.username})

    owner_headers = {"Authorization": f"Bearer {owner_token}"}
    other_headers = {"Authorization": f"Bearer {other_token}"}
    transport = ASGITransport(app=app)
    fandom_id = None

    try:
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            # 1. Create fandom
            slug = f"del-fandom-{suffix}"
            create_res = await client.post(
                "/api/v1/fandoms",
                headers=owner_headers,
                json={
                    "name": "To Be Deleted",
                    "slug": slug,
                    "category": "Âm nhạc",
                },
            )
            assert create_res.status_code == 201
            fandom_id = uuid.UUID(create_res.json()["fandom_id"])

            # Verify channels and roles were created
            async with AsyncSessionLocal() as db:
                channels = (await db.execute(select(Channel).where(Channel.fandom_id == fandom_id))).scalars().all()
                assert len(channels) == 3

            # 2. Non-owner trying to delete -> 403 Forbidden
            non_owner_res = await client.request(
                "DELETE",
                f"/api/v1/fandoms/{slug}",
                headers=other_headers,
                json={"password": password},
            )
            assert non_owner_res.status_code == 403

            # 3. Owner with wrong password -> 400 Bad Request
            wrong_pass_res = await client.request(
                "DELETE",
                f"/api/v1/fandoms/{slug}",
                headers=owner_headers,
                json={"password": "WrongPassword999!"},
            )
            assert wrong_pass_res.status_code == 400
            assert "Mật khẩu xác nhận không chính xác" in wrong_pass_res.json()["detail"]

            # 4. Owner with correct password -> 200 OK
            del_res = await client.request(
                "DELETE",
                f"/api/v1/fandoms/{slug}",
                headers=owner_headers,
                json={"password": password},
            )
            assert del_res.status_code == 200
            data = del_res.json()
            assert data["success"] is True
            assert str(data["fandom_id"]) == str(fandom_id)

            # 5. Verify in DB that fandom and cascade entities are completely removed
            async with AsyncSessionLocal() as db:
                f_check = (await db.execute(select(Fandom).where(Fandom.id == fandom_id))).scalar_one_or_none()
                assert f_check is None

                ch_check = (await db.execute(select(Channel).where(Channel.fandom_id == fandom_id))).scalars().all()
                assert len(ch_check) == 0

                role_check = (await db.execute(select(Role).where(Role.fandom_id == fandom_id))).scalars().all()
                assert len(role_check) == 0

                member_check = (await db.execute(select(FandomMember).where(FandomMember.fandom_id == fandom_id))).scalars().all()
                assert len(member_check) == 0

            # 6. Preview should return 404 now
            preview_del = await client.get(f"/api/v1/fandoms/{slug}/preview")
            assert preview_del.status_code == 404
            fandom_id = None
    finally:
        await _cleanup_entities([owner.id, other_user.id], [fandom_id] if fandom_id else [])
