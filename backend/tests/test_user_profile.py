import uuid
import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import delete

from app.core.database import AsyncSessionLocal
from app.core.redis import get_redis_client
from app.core.security import create_access_token, get_password_hash
from app.main import app
from app.modules.fandom.models import Fandom, FandomMember
from app.modules.identity.models import User


async def _cleanup_test_data(user_ids: list[uuid.UUID], fandom_ids: list[uuid.UUID]) -> None:
    async with AsyncSessionLocal() as db:
        if fandom_ids:
            await db.execute(delete(FandomMember).where(FandomMember.fandom_id.in_(fandom_ids)))
            await db.execute(delete(Fandom).where(Fandom.id.in_(fandom_ids)))
        if user_ids:
            await db.execute(delete(User).where(User.id.in_(user_ids)))
        await db.commit()


@pytest.mark.asyncio
async def test_get_and_update_my_profile_and_banner():
    """
    Verifies that:
    1. GET /api/v1/users/me includes banner_url.
    2. PUT /api/v1/users/me and PUT /api/v1/users/me/profile updates display_name, bio, avatar_url, and banner_url.
    3. Input validation enforces max length: display_name <= 50, bio <= 250.
    """
    suffix = uuid.uuid4().hex[:8]
    test_user = User(
        username=f"profileuser_{suffix}",
        email=f"profile_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("Password123!"),
        display_name="Profile Test User",
        bio="Initial short bio",
        avatar_url="https://res.cloudinary.com/fanspace/image/upload/v1/initial_avatar.jpg",
        banner_url="https://res.cloudinary.com/fanspace/image/upload/v1/initial_banner.jpg",
        is_active=True,
    )

    async with AsyncSessionLocal() as db:
        db.add(test_user)
        await db.commit()
        await db.refresh(test_user)
        user_id = test_user.id

    token = create_access_token(data={"sub": str(user_id)})
    headers = {"Authorization": f"Bearer {token}"}

    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            # 1. GET /api/v1/users/me
            res_me = await client.get("/api/v1/users/me", headers=headers)
            assert res_me.status_code == 200
            data_me = res_me.json()
            assert data_me["username"] == f"profileuser_{suffix}"
            assert data_me["display_name"] == "Profile Test User"
            assert data_me["banner_url"] == "https://res.cloudinary.com/fanspace/image/upload/v1/initial_banner.jpg"
            assert data_me["avatar_url"] == "https://res.cloudinary.com/fanspace/image/upload/v1/initial_avatar.jpg"
            assert data_me["bio"] == "Initial short bio"

            # 2. PUT /api/v1/users/me
            new_banner = "https://res.cloudinary.com/fanspace/image/upload/v1/new_banner.jpg"
            new_avatar = "https://res.cloudinary.com/fanspace/image/upload/v1/new_avatar.jpg"
            res_update = await client.put(
                "/api/v1/users/me",
                headers=headers,
                json={
                    "display_name": "Updated Name",
                    "bio": "Updated bio describing my passions.",
                    "avatar_url": new_avatar,
                    "banner_url": new_banner,
                },
            )
            assert res_update.status_code == 200
            data_updated = res_update.json()
            assert data_updated["display_name"] == "Updated Name"
            assert data_updated["bio"] == "Updated bio describing my passions."
            assert data_updated["avatar_url"] == new_avatar
            assert data_updated["banner_url"] == new_banner

            # 3. PUT /api/v1/users/me/profile (alias)
            res_alias = await client.put(
                "/api/v1/users/me/profile",
                headers=headers,
                json={
                    "display_name": "Alias Name",
                    "bio": "Alias bio",
                },
            )
            assert res_alias.status_code == 200
            assert res_alias.json()["display_name"] == "Alias Name"

            # 4. Validation: display_name > 50 chars rejected
            res_long_name = await client.put(
                "/api/v1/users/me",
                headers=headers,
                json={"display_name": "A" * 51},
            )
            assert res_long_name.status_code == 422

            # 5. Validation: bio > 250 chars rejected
            res_long_bio = await client.put(
                "/api/v1/users/me",
                headers=headers,
                json={"bio": "B" * 251},
            )
            assert res_long_bio.status_code == 422

    finally:
        await _cleanup_test_data([user_id], [])


@pytest.mark.asyncio
async def test_get_user_public_card_projection_and_caching():
    """
    Verifies that:
    1. GET /api/v1/users/{identifier}/card and /profile return UserProfilePublic schema.
    2. Correct counts of owned public fandoms and joined fandoms are calculated.
    3. Sensitive attributes (email, coin_balance, password_hash) are excluded.
    4. Caching in Redis functions properly.
    5. Non-existent identifier returns 404.
    """
    suffix = uuid.uuid4().hex[:8]
    creator = User(
        username=f"creator_{suffix}",
        email=f"creator_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("Pass1234"),
        display_name="KOL Creator",
        bio="Official verified creator in FanSpace",
        avatar_url="https://res.cloudinary.com/fanspace/image/upload/v1/creator_avatar.jpg",
        banner_url="https://res.cloudinary.com/fanspace/image/upload/v1/creator_banner.jpg",
        system_role="USER",
        is_active=True,
    )
    other_owner = User(
        username=f"other_{suffix}",
        email=f"other_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("Pass1234"),
        display_name="Other Owner",
        is_active=True,
    )

    async with AsyncSessionLocal() as db:
        db.add_all([creator, other_owner])
        await db.flush()

        # Fandom owned by creator (public)
        fandom_owned_pub = Fandom(
            name=f"Creator Club {suffix}",
            slug=f"creator-club-{suffix}",
            is_public=True,
            member_count=10,
            owner_id=creator.id,
        )
        # Fandom owned by creator (private - should not increment public owned count)
        fandom_owned_priv = Fandom(
            name=f"Creator VIP {suffix}",
            slug=f"creator-vip-{suffix}",
            is_public=False,
            member_count=2,
            owner_id=creator.id,
        )
        # Fandom owned by other owner, creator joins it
        fandom_other = Fandom(
            name=f"Other Club {suffix}",
            slug=f"other-club-{suffix}",
            is_public=True,
            member_count=50,
            owner_id=other_owner.id,
        )
        db.add_all([fandom_owned_pub, fandom_owned_priv, fandom_other])
        await db.flush()

        # Creator joins fandom_other
        membership = FandomMember(
            fandom_id=fandom_other.id,
            user_id=creator.id,
            status="ACTIVE",
        )
        db.add(membership)
        await db.commit()

        user_ids = [creator.id, other_owner.id]
        fandom_ids = [fandom_owned_pub.id, fandom_owned_priv.id, fandom_other.id]
        creator_id_str = str(creator.id)
        creator_username = creator.username

    redis = await get_redis_client()
    await redis.delete(f"cache:user:card:{creator_id_str}")
    await redis.delete(f"cache:user:card:{creator_username.lower()}")

    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            # 1. Fetch by UUID
            res_by_id = await client.get(f"/api/v1/users/{creator_id_str}/card")
            assert res_by_id.status_code == 200
            card_id = res_by_id.json()
            assert card_id["id"] == creator_id_str
            assert card_id["username"] == creator_username
            assert card_id["display_name"] == "KOL Creator"
            assert card_id["banner_url"] == "https://res.cloudinary.com/fanspace/image/upload/v1/creator_banner.jpg"
            assert card_id["avatar_url"] == "https://res.cloudinary.com/fanspace/image/upload/v1/creator_avatar.jpg"
            assert card_id["bio"] == "Official verified creator in FanSpace"
            assert card_id["fandoms_owned_count"] == 1  # only public
            assert card_id["fandoms_joined_count"] == 1  # joined fandom_other
            assert "email" not in card_id
            assert "coin_balance" not in card_id
            assert "password_hash" not in card_id

            # 2. Fetch by Username (case-insensitive) using /profile alias
            res_by_user = await client.get(f"/api/v1/users/{creator_username.upper()}/profile")
            assert res_by_user.status_code == 200
            card_user = res_by_user.json()
            assert card_user["id"] == creator_id_str
            assert card_user["username"] == creator_username

            # 3. Verify Redis cache was populated
            cached_val = await redis.get(f"cache:user:card:{creator_id_str}")
            assert cached_val is not None

            # 4. Non-existent user returns 404
            res_404 = await client.get("/api/v1/users/nonexistent_user_999999/card")
            assert res_404.status_code == 404

    finally:
        await redis.delete(f"cache:user:card:{creator_id_str}")
        await redis.delete(f"cache:user:card:{creator_username.lower()}")
        await _cleanup_test_data(user_ids, fandom_ids)
