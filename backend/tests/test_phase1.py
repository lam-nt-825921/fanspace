import pytest
import uuid
from httpx import ASGITransport, AsyncClient
from app.main import app
from app.core.database import init_db


@pytest.mark.asyncio
async def test_auth_register_and_login():
    unique_id = uuid.uuid4().hex[:8]
    email = f"fan_{unique_id}@example.com"
    username = f"fan_{unique_id}"
    password = "SuperSecurePassword123!"

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Register
        reg_res = await client.post(
            "/api/v1/auth/register",
            json={
                "email": email,
                "username": username,
                "password": password,
                "display_name": "Sky Fan 01",
            },
        )
        assert reg_res.status_code == 201
        reg_data = reg_res.json()
        assert reg_data["success"] is True
        assert "tokens" in reg_data
        assert "access_token" in reg_data["tokens"]
        access_token = reg_data["tokens"]["access_token"]

        # 2. Duplicate register fails
        dup_res = await client.post(
            "/api/v1/auth/register",
            json={
                "email": email,
                "username": username,
                "password": password,
                "display_name": "Sky Fan Duplicate",
            },
        )
        assert dup_res.status_code == 400

        # 3. Login with wrong password fails
        bad_login = await client.post(
            "/api/v1/auth/login",
            json={"email": email, "password": "WrongPassword!"},
        )
        assert bad_login.status_code == 401

        # 4. Login with right password succeeds
        good_login = await client.post(
            "/api/v1/auth/login",
            json={"email": email, "password": password},
        )
        assert good_login.status_code == 200
        active_token = good_login.json()["tokens"]["access_token"]

        # 5. Get current user profile (/me)
        me_res = await client.get(
            "/api/v1/users/me",
            headers={"Authorization": f"Bearer {active_token}"},
        )
        assert me_res.status_code == 200
        me_data = me_res.json()
        assert me_data["username"] == username
        assert me_data["coin_balance"] == 0  # No free money: real balance starts at 0


@pytest.mark.asyncio
async def test_dev_login_endpoint_removed():
    """Verify that dev backdoor endpoint has been completely removed."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        res = await client.post(
            "/api/v1/auth/dev-login",
            json={"username": "hacker_bot"},
        )
        assert res.status_code == 404 or res.status_code == 405


@pytest.mark.asyncio
async def test_fandom_creation_and_discovery():
    unique_id = uuid.uuid4().hex[:8]
    slug = f"son-tung-{unique_id}"

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Register a real owner user
        reg_res = await client.post(
            "/api/v1/auth/register",
            json={
                "email": f"owner_{unique_id}@example.com",
                "username": f"owner_{unique_id}",
                "password": "StrongPassword123!",
                "display_name": f"Owner {unique_id}",
            },
        )
        assert reg_res.status_code == 201
        token = reg_res.json()["tokens"]["access_token"]

        # 2. Create Fandom
        create_res = await client.post(
            "/api/v1/fandoms",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "name": f"Sơn Tùng M-TP Fanclub {unique_id}",
                "slug": slug,
                "description": "Cộng đồng người hâm mộ chính thức của Sơn Tùng M-TP",
                "category": "Âm nhạc",
                "admission_mode": "OPEN",
            },
        )
        assert create_res.status_code == 201
        assert create_res.json()["success"] is True
        assert create_res.json()["slug"] == slug

        # 3. Create duplicate slug fails
        dup_res = await client.post(
            "/api/v1/fandoms",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "name": "Another Fandom",
                "slug": slug,
                "category": "Âm nhạc",
            },
        )
        assert dup_res.status_code == 400

        # 4. Public Directory listing
        pub_res = await client.get("/api/v1/fandoms/public")
        assert pub_res.status_code == 200
        fandoms = pub_res.json()
        assert any(f["slug"] == slug for f in fandoms)

        # 5. Search Public Directory
        search_res = await client.get(f"/api/v1/fandoms/public?search={unique_id}")
        assert search_res.status_code == 200
        matched = search_res.json()
        assert len(matched) >= 1
        assert matched[0]["slug"] == slug

        # 6. Preview Fandom
        prev_res = await client.get(f"/api/v1/fandoms/{slug}/preview")
        assert prev_res.status_code == 200
        prev_data = prev_res.json()
        assert prev_data["name"] == f"Sơn Tùng M-TP Fanclub {unique_id}"
        assert prev_data["admission_mode"] == "OPEN"
        assert prev_data["member_count"] == 1
