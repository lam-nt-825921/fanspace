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


async def _cleanup_test_entities(user_ids: list[uuid.UUID], fandom_ids: list[uuid.UUID]) -> None:
    async with AsyncSessionLocal() as db:
        if fandom_ids:
            await db.execute(delete(FandomMember).where(FandomMember.fandom_id.in_(fandom_ids)))
            await db.execute(delete(Fandom).where(Fandom.id.in_(fandom_ids)))
        if user_ids:
            await db.execute(delete(User).where(User.id.in_(user_ids)))
        await db.commit()


@pytest.mark.asyncio
async def test_public_fandom_directory_search_accent_and_case_insensitive():
    """
    Verifies that GET /api/v1/fandoms/public supports case-insensitive and
    Vietnamese accent-insensitive search across fandom name, slug, owner name,
    and owner ID, while ignoring unrelated text inside description.
    """
    suffix = uuid.uuid4().hex[:8]
    owner_one = User(
        username=f"nguyentronglam_{suffix}",
        email=f"lam_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("TestPass123"),
        display_name="Nguyễn Trọng Lâm",
        is_active=True,
    )
    owner_two = User(
        username=f"tranminhduc_{suffix}",
        email=f"duc_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("TestPass123"),
        display_name="Trần Minh Đức",
        is_active=True,
    )

    async with AsyncSessionLocal() as db:
        db.add_all([owner_one, owner_two])
        await db.flush()

        fandom_one = Fandom(
            name=f"Hội Đam Mê Sơn Tùng M-TP {suffix}",
            slug=f"sky-mtp-{suffix}",
            description="Cộng đồng dành cho những người yêu âm nhạc Việt Nam đặc sắc.",
            category="Music / K-Pop / US-UK",
            admission_mode="OPEN",
            is_public=True,
            member_count=250,
            owner_id=owner_one.id,
        )
        fandom_two = Fandom(
            name=f"Cộng Đồng Liên Minh Huyền Thoại {suffix}",
            slug=f"lol-vietnam-{suffix}",
            description="Nơi thảo luận chiến thuật từ khóa bí mật xylophone_secret_keyword.",
            category="Gaming / Esports",
            admission_mode="APPROVAL_REQUIRED",
            is_public=True,
            member_count=120,
            owner_id=owner_two.id,
        )
        fandom_private = Fandom(
            name=f"Hội Đam Mê Bí Mật {suffix}",
            slug=f"private-club-{suffix}",
            description="Fandom riêng tư không hiển thị công khai.",
            category="Music / K-Pop / US-UK",
            admission_mode="APPROVAL_REQUIRED",
            is_public=False,
            member_count=500,
            owner_id=owner_one.id,
        )
        db.add_all([fandom_one, fandom_two, fandom_private])
        await db.commit()
        user_ids = [owner_one.id, owner_two.id]
        fandom_ids = [fandom_one.id, fandom_two.id, fandom_private.id]
        owner_one_id_str = str(owner_one.id)

    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            # 1. Search by Vietnamese unaccented & lowercase query matching accented Fandom name ("Đam Mê Sơn Tùng")
            res_name = await client.get(
                "/api/v1/fandoms/public",
                params={"search": f"dam me son tung m-tp {suffix}"},
            )
            assert res_name.status_code == 200
            items_name = res_name.json()
            assert len(items_name) == 1
            assert items_name[0]["slug"] == f"sky-mtp-{suffix}"

            # 2. Search by uppercase accented query ("HỘI ĐAM MÊ") and verify private fandom is excluded
            res_upper = await client.get(
                "/api/v1/fandoms/public",
                params={"search": f"HỘI ĐAM MÊ"},
            )
            assert res_upper.status_code == 200
            slugs_upper = [item["slug"] for item in res_upper.json()]
            assert f"sky-mtp-{suffix}" in slugs_upper
            assert f"private-club-{suffix}" not in slugs_upper

            # 3. Search by Fandom slug
            res_slug = await client.get(
                "/api/v1/fandoms/public",
                params={"search": f"lol-vietnam-{suffix}"},
            )
            assert res_slug.status_code == 200
            assert len(res_slug.json()) == 1
            assert res_slug.json()[0]["slug"] == f"lol-vietnam-{suffix}"

            # 4. Search by Owner display_name without accents ("nguyen trong lam")
            res_owner_name = await client.get(
                "/api/v1/fandoms/public",
                params={"search": "nguyen trong lam"},
            )
            assert res_owner_name.status_code == 200
            slugs_owner = [item["slug"] for item in res_owner_name.json()]
            assert f"sky-mtp-{suffix}" in slugs_owner
            assert f"private-club-{suffix}" not in slugs_owner

            # 5. Search by Owner display_name with 'đ/Đ' normalization ("tran minh duc")
            res_owner_d = await client.get(
                "/api/v1/fandoms/public",
                params={"search": "tran minh duc"},
            )
            assert res_owner_d.status_code == 200
            slugs_owner_d = [item["slug"] for item in res_owner_d.json()]
            assert f"lol-vietnam-{suffix}" in slugs_owner_d

            # 6. Search by Owner ID (exact UUID string)
            res_owner_id = await client.get(
                "/api/v1/fandoms/public",
                params={"search": owner_one_id_str},
            )
            assert res_owner_id.status_code == 200
            slugs_owner_id = [item["slug"] for item in res_owner_id.json()]
            assert f"sky-mtp-{suffix}" in slugs_owner_id

            # 7. Verify words only inside `description` do NOT match
            res_desc = await client.get(
                "/api/v1/fandoms/public",
                params={"search": "xylophone_secret_keyword"},
            )
            assert res_desc.status_code == 200
            assert res_desc.json() == []
    finally:
        await _cleanup_test_entities(user_ids, fandom_ids)


@pytest.mark.asyncio
async def test_public_fandom_directory_sort_pagination_and_summary_truncation():
    """
    Verifies sorting modes (popular, newest, name_asc), bounded offset pagination,
    and 160-character summary description truncation in GET /api/v1/fandoms/public.
    """
    suffix = uuid.uuid4().hex[:8]
    category_tag = f"TestCat-{suffix}"
    long_description = "A" * 220

    owner = User(
        username=f"sorter_{suffix}",
        email=f"sorter_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("TestPass123"),
        display_name="Sorter Owner",
        is_active=True,
    )

    async with AsyncSessionLocal() as db:
        db.add(owner)
        await db.flush()

        f_alpha = Fandom(
            name=f"Alpha Fandom {suffix}",
            slug=f"alpha-{suffix}",
            description=long_description,
            category=category_tag,
            member_count=50,
            owner_id=owner.id,
        )
        f_beta = Fandom(
            name=f"Beta Fandom {suffix}",
            slug=f"beta-{suffix}",
            description="Short description",
            category=category_tag,
            member_count=300,
            owner_id=owner.id,
        )
        f_gamma = Fandom(
            name=f"Gamma Fandom {suffix}",
            slug=f"gamma-{suffix}",
            description="Medium description",
            category=category_tag,
            member_count=150,
            owner_id=owner.id,
        )
        db.add_all([f_alpha, f_beta, f_gamma])
        await db.commit()
        user_ids = [owner.id]
        fandom_ids = [f_alpha.id, f_beta.id, f_gamma.id]

    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            # 1. Default sort = popular (member_count DESC: beta=300, gamma=150, alpha=50)
            res_pop = await client.get(
                "/api/v1/fandoms/public",
                params={"category": category_tag, "sort_by": "popular"},
            )
            assert res_pop.status_code == 200
            items_pop = res_pop.json()
            assert [i["slug"] for i in items_pop] == [
                f"beta-{suffix}",
                f"gamma-{suffix}",
                f"alpha-{suffix}",
            ]

            # Verify summary truncation (<= 160 chars ending with '...') and omitted heavy fields
            alpha_summary = items_pop[2]
            assert len(alpha_summary["description"]) == 160
            assert alpha_summary["description"].endswith("...")
            assert "rules_tos" not in alpha_summary
            assert "illustration_urls" not in alpha_summary
            assert alpha_summary["owner_id"] == str(owner.id)
            assert alpha_summary["admission_mode"] == "OPEN"

            # 2. Sort by name_asc (Alpha, Beta, Gamma)
            res_name = await client.get(
                "/api/v1/fandoms/public",
                params={"category": category_tag, "sort_by": "name_asc"},
            )
            assert res_name.status_code == 200
            assert [i["slug"] for i in res_name.json()] == [
                f"alpha-{suffix}",
                f"beta-{suffix}",
                f"gamma-{suffix}",
            ]

            # 3. Pagination (limit=1, offset=1 on popular -> gamma)
            res_page = await client.get(
                "/api/v1/fandoms/public",
                params={"category": category_tag, "sort_by": "popular", "limit": 1, "offset": 1},
            )
            assert res_page.status_code == 200
            page_items = res_page.json()
            assert len(page_items) == 1
            assert page_items[0]["slug"] == f"gamma-{suffix}"

            # 4. Bounded pagination validation (limit > 50 or offset > 1000 -> 422)
            res_bad_limit = await client.get("/api/v1/fandoms/public", params={"limit": 51})
            assert res_bad_limit.status_code == 422

            res_bad_offset = await client.get("/api/v1/fandoms/public", params={"offset": 1001})
            assert res_bad_offset.status_code == 422
    finally:
        await _cleanup_test_entities(user_ids, fandom_ids)


@pytest.mark.asyncio
async def test_fandom_profile_preview_contextual_flags_and_redis_cache():
    """
    Verifies GET /api/v1/fandoms/{slug}/preview returns complete FandomDetail
    (full untruncated description, rules_tos, illustration_urls) and accurately
    resolves is_owner / is_member for Guest, Member, and Owner, while populating
    Redis Cache-Aside keys.
    """
    suffix = uuid.uuid4().hex[:8]
    owner = User(
        username=f"owner_prev_{suffix}",
        email=f"owner_prev_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("TestPass123"),
        display_name="Chủ Fandom",
        is_active=True,
    )
    member = User(
        username=f"member_prev_{suffix}",
        email=f"member_prev_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("TestPass123"),
        display_name="Thành Viên Fandom",
        is_active=True,
    )
    stranger = User(
        username=f"stranger_prev_{suffix}",
        email=f"stranger_prev_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("TestPass123"),
        display_name="Khách Vãng Lai",
        is_active=True,
    )

    full_description = "Mô tả đầy đủ của Fandom dài hơn 160 ký tự: " + ("Nội dung chi tiết " * 15)
    slug = f"preview-fandom-{suffix}"

    async with AsyncSessionLocal() as db:
        db.add_all([owner, member, stranger])
        await db.flush()

        fandom = Fandom(
            name=f"Fandom Preview {suffix}",
            slug=slug,
            description=full_description,
            category="Anime / Manga",
            avatar_url="https://res.cloudinary.com/demo/image/upload/v1/fanspace/fandoms/avatars/a.webp",
            banner_url="https://res.cloudinary.com/demo/image/upload/v1/fanspace/fandoms/banners/b.webp",
            illustration_urls=[
                "https://res.cloudinary.com/demo/image/upload/v1/fanspace/fandoms/illustrations/1.jpg",
                "https://res.cloudinary.com/demo/video/upload/v1/fanspace/fandoms/videos/intro.mp4",
            ],
            admission_mode="APPROVAL_REQUIRED",
            is_public=True,
            rules_tos="1. Tôn trọng thành viên.\n2. Không spam.",
            member_count=2,
            owner_id=owner.id,
        )
        db.add(fandom)
        await db.flush()

        db.add_all(
            [
                FandomMember(fandom_id=fandom.id, user_id=owner.id, status="ACTIVE"),
                FandomMember(fandom_id=fandom.id, user_id=member.id, status="ACTIVE"),
            ]
        )
        await db.commit()
        user_ids = [owner.id, member.id, stranger.id]
        fandom_ids = [fandom.id]
        owner_token = create_access_token(data={"sub": str(owner.id)})
        member_token = create_access_token(data={"sub": str(member.id)})
        stranger_token = create_access_token(data={"sub": str(stranger.id)})

    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            # 1. Guest request (no Authorization header)
            res_guest = await client.get(f"/api/v1/fandoms/{slug}/preview")
            assert res_guest.status_code == 200
            data_guest = res_guest.json()
            assert data_guest["description"] == full_description
            assert data_guest["rules_tos"] == "1. Tôn trọng thành viên.\n2. Không spam."
            assert len(data_guest["illustration_urls"]) == 2
            assert data_guest["is_owner"] is False
            assert data_guest["is_member"] is False
            assert data_guest["owner_name"] == "Chủ Fandom"

            # Verify Redis cache key was populated
            redis = get_redis_client()
            cached_payload = await redis.get(f"cache:fandom:preview:{slug}")
            assert cached_payload is not None

            # 2. Authenticated Owner request (reads base metadata from Redis cache + computes flags)
            res_owner = await client.get(
                f"/api/v1/fandoms/{slug}/preview",
                headers={"Authorization": f"Bearer {owner_token}"},
            )
            assert res_owner.status_code == 200
            data_owner = res_owner.json()
            assert data_owner["is_owner"] is True
            assert data_owner["is_member"] is True

            # 3. Authenticated Member request
            res_member = await client.get(
                f"/api/v1/fandoms/{slug}/preview",
                headers={"Authorization": f"Bearer {member_token}"},
            )
            assert res_member.status_code == 200
            data_member = res_member.json()
            assert data_member["is_owner"] is False
            assert data_member["is_member"] is True

            # 4. Authenticated Non-Member request
            res_stranger = await client.get(
                f"/api/v1/fandoms/{slug}/preview",
                headers={"Authorization": f"Bearer {stranger_token}"},
            )
            assert res_stranger.status_code == 200
            data_stranger = res_stranger.json()
            assert data_stranger["is_owner"] is False
            assert data_stranger["is_member"] is False
    finally:
        await _cleanup_test_entities(user_ids, fandom_ids)


@pytest.mark.asyncio
async def test_create_fandom_illustration_validation_and_cache_invalidation():
    """
    Verifies that POST /api/v1/fandoms enforces at most 5 illustration URLs and
    at most 1 short video, and invalidates the public fandom list cache upon creation.
    """
    suffix = uuid.uuid4().hex[:8]
    owner = User(
        username=f"creator_{suffix}",
        email=f"creator_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("TestPass123"),
        display_name="Creator User",
        is_active=True,
    )

    async with AsyncSessionLocal() as db:
        db.add(owner)
        await db.commit()
        user_id = owner.id
        token = create_access_token(data={"sub": str(owner.id)})

    created_fandom_ids: list[uuid.UUID] = []
    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            # Prime the Redis list cache before creation
            await client.get(
                "/api/v1/fandoms/public",
                params={"category": "Game & Esports", "sort_by": "popular", "limit": 20, "offset": 0},
            )
            redis = get_redis_client()
            list_cache_key = "cache:fandoms:list:game & esports:popular:20:0"
            assert await redis.get(list_cache_key) is not None

            # Reject > 1 short video in illustration_urls with 400 Bad Request
            res_two_videos = await client.post(
                "/api/v1/fandoms",
                headers={"Authorization": f"Bearer {token}"},
                json={
                    "name": f"Two Videos Fandom {suffix}",
                    "slug": f"two-videos-{suffix}",
                    "category": "Game & Esports",
                    "illustration_urls": [
                        "https://res.cloudinary.com/demo/video/upload/v1/v1.mp4",
                        "https://res.cloudinary.com/demo/video/upload/v1/v2.webm",
                    ],
                },
            )
            assert res_two_videos.status_code == 400

            # Create valid fandom with 1 video + 2 images
            res_valid = await client.post(
                "/api/v1/fandoms",
                headers={"Authorization": f"Bearer {token}"},
                json={
                    "name": f"Valid Showcase Fandom {suffix}",
                    "slug": f"valid-showcase-{suffix}",
                    "category": "Game & Esports",
                    "illustration_urls": [
                        "https://res.cloudinary.com/demo/image/upload/v1/img1.jpg",
                        "https://res.cloudinary.com/demo/image/upload/v1/img2.webp",
                        "https://res.cloudinary.com/demo/video/upload/v1/clip.mp4",
                    ],
                },
            )
            assert res_valid.status_code == 201
            body = res_valid.json()
            assert body["success"] is True
            created_fandom_ids.append(uuid.UUID(body["fandom_id"]))

            # Verify Redis list cache was invalidated upon fandom creation
            assert await redis.get(list_cache_key) is None

            # Verify preview returns the created illustration_urls and owner context
            res_preview = await client.get(
                f"/api/v1/fandoms/valid-showcase-{suffix}/preview",
                headers={"Authorization": f"Bearer {token}"},
            )
            assert res_preview.status_code == 200
            preview_data = res_preview.json()
            assert len(preview_data["illustration_urls"]) == 3
            assert preview_data["is_owner"] is True
            assert preview_data["is_member"] is True
    finally:
        await _cleanup_test_entities([user_id], created_fandom_ids)
