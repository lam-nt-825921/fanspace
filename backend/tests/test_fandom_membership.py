import uuid
from datetime import datetime, timedelta, timezone
import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import delete

from app.core.database import AsyncSessionLocal
from app.core.redis import get_redis_client
from app.core.security import create_access_token, get_password_hash
from app.main import app
from app.modules.fandom.models import Fandom, FandomInvite, FandomJoinRequest, FandomMember
from app.modules.identity.models import User


async def _cleanup_test_entities(user_ids: list[uuid.UUID], fandom_ids: list[uuid.UUID]) -> None:
    async with AsyncSessionLocal() as db:
        if fandom_ids:
            await db.execute(delete(FandomInvite).where(FandomInvite.fandom_id.in_(fandom_ids)))
            await db.execute(delete(FandomJoinRequest).where(FandomJoinRequest.fandom_id.in_(fandom_ids)))
            await db.execute(delete(FandomMember).where(FandomMember.fandom_id.in_(fandom_ids)))
            await db.execute(delete(Fandom).where(Fandom.id.in_(fandom_ids)))
        if user_ids:
            await db.execute(delete(User).where(User.id.in_(user_ids)))
        await db.commit()


@pytest.mark.asyncio
async def test_join_and_leave_open_fandom():
    """
    Test joining an OPEN public fandom:
    - User joins immediately, member_count increments.
    - Subsequent join fails with 400.
    - User leaves, member_count decrements.
    - Subsequent leave fails with 400.
    """
    suffix = uuid.uuid4().hex[:8]
    owner = User(
        username=f"owner_{suffix}",
        email=f"owner_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("Password123!"),
        display_name="Fandom Owner",
        is_active=True,
    )
    member = User(
        username=f"member_{suffix}",
        email=f"member_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("Password123!"),
        display_name="Fan Member",
        is_active=True,
    )

    async with AsyncSessionLocal() as db:
        db.add_all([owner, member])
        await db.flush()

        fandom = Fandom(
            name=f"Open Fandom {suffix}",
            slug=f"open-fandom-{suffix}",
            description="Cộng đồng mở hoàn toàn",
            category="Music / K-Pop / US-UK",
            admission_mode="OPEN",
            is_public=True,
            member_count=1,
            owner_id=owner.id,
        )
        db.add(fandom)
        await db.flush()

        db.add(FandomMember(fandom_id=fandom.id, user_id=owner.id, status="ACTIVE"))
        await db.commit()

        owner_id = owner.id
        member_id = member.id
        fandom_id = fandom.id
        slug = fandom.slug

    try:
        member_token = create_access_token(data={"sub": str(member_id)})
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            # 1. Member joins OPEN fandom
            res = await ac.post(
                f"/api/v1/fandoms/{slug}/join",
                headers={"Authorization": f"Bearer {member_token}"},
            )
            assert res.status_code == 200, res.text
            data = res.json()
            assert data["status"] == "JOINED"
            assert data["slug"] == slug

            # 2. Duplicate join returns 400
            dup_res = await ac.post(
                f"/api/v1/fandoms/{slug}/join",
                headers={"Authorization": f"Bearer {member_token}"},
            )
            assert dup_res.status_code == 400
            assert "đã là thành viên" in dup_res.json()["detail"]

            # 3. Preview shows user is member & member_count incremented
            preview_res = await ac.get(
                f"/api/v1/fandoms/{slug}",
                headers={"Authorization": f"Bearer {member_token}"},
            )
            assert preview_res.status_code == 200
            assert preview_res.json()["is_member"] is True
            assert preview_res.json()["is_pending_request"] is False
            assert preview_res.json()["member_count"] == 2

            # 4. Member leaves fandom
            leave_res = await ac.post(
                f"/api/v1/fandoms/{slug}/leave",
                headers={"Authorization": f"Bearer {member_token}"},
            )
            assert leave_res.status_code == 200
            assert leave_res.json()["success"] is True

            # 5. Preview shows user is no longer member & member_count decremented
            preview_after = await ac.get(
                f"/api/v1/fandoms/{slug}",
                headers={"Authorization": f"Bearer {member_token}"},
            )
            assert preview_after.status_code == 200
            assert preview_after.json()["is_member"] is False
            assert preview_after.json()["member_count"] == 1

            # 6. Subsequent leave returns 400
            dup_leave = await ac.post(
                f"/api/v1/fandoms/{slug}/leave",
                headers={"Authorization": f"Bearer {member_token}"},
            )
            assert dup_leave.status_code == 400
    finally:
        await _cleanup_test_entities([owner_id, member_id], [fandom_id])


@pytest.mark.asyncio
async def test_owner_cannot_leave_own_fandom():
    """
    Test that fandom owner cannot leave their own fandom.
    """
    suffix = uuid.uuid4().hex[:8]
    owner = User(
        username=f"owner_{suffix}",
        email=f"owner_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("Password123!"),
        display_name="Fandom Owner",
        is_active=True,
    )

    async with AsyncSessionLocal() as db:
        db.add(owner)
        await db.flush()

        fandom = Fandom(
            name=f"Owner Fandom {suffix}",
            slug=f"owner-fandom-{suffix}",
            description="Test owner cannot leave",
            category="Music / K-Pop / US-UK",
            admission_mode="OPEN",
            is_public=True,
            member_count=1,
            owner_id=owner.id,
        )
        db.add(fandom)
        await db.flush()

        db.add(FandomMember(fandom_id=fandom.id, user_id=owner.id, status="ACTIVE"))
        await db.commit()

        owner_id = owner.id
        fandom_id = fandom.id
        slug = fandom.slug

    try:
        owner_token = create_access_token(data={"sub": str(owner_id)})
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            res = await ac.post(
                f"/api/v1/fandoms/{slug}/leave",
                headers={"Authorization": f"Bearer {owner_token}"},
            )
            assert res.status_code == 400
            assert "Chủ sở hữu" in res.json()["detail"]
    finally:
        await _cleanup_test_entities([owner_id], [fandom_id])


@pytest.mark.asyncio
async def test_join_approval_fandom_and_cancellation():
    """
    Test joining APPROVAL fandom:
    - Creates PENDING request, member_count unchanged.
    - Duplicate request returns 409 Conflict.
    - User can cancel pending request.
    - Subsequent cancellation returns 404.
    """
    suffix = uuid.uuid4().hex[:8]
    owner = User(
        username=f"owner_{suffix}",
        email=f"owner_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("Password123!"),
        display_name="Fandom Owner",
        is_active=True,
    )
    user = User(
        username=f"applicant_{suffix}",
        email=f"applicant_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("Password123!"),
        display_name="Applicant",
        is_active=True,
    )

    async with AsyncSessionLocal() as db:
        db.add_all([owner, user])
        await db.flush()

        fandom = Fandom(
            name=f"Approval Fandom {suffix}",
            slug=f"approval-fandom-{suffix}",
            description="Cộng đồng xét duyệt",
            category="Anime / Manga / Cosplay",
            admission_mode="APPROVAL",
            is_public=True,
            member_count=1,
            owner_id=owner.id,
        )
        db.add(fandom)
        await db.flush()

        db.add(FandomMember(fandom_id=fandom.id, user_id=owner.id, status="ACTIVE"))
        await db.commit()

        owner_id = owner.id
        user_id = user.id
        fandom_id = fandom.id
        slug = fandom.slug

    try:
        user_token = create_access_token(data={"sub": str(user_id)})
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            # 1. Submit join request
            res = await ac.post(
                f"/api/v1/fandoms/{slug}/join",
                headers={"Authorization": f"Bearer {user_token}"},
            )
            assert res.status_code == 200
            data = res.json()
            assert data["status"] == "REQUEST_SUBMITTED"

            # 2. Duplicate join request yields 409 Conflict
            dup_res = await ac.post(
                f"/api/v1/fandoms/{slug}/join",
                headers={"Authorization": f"Bearer {user_token}"},
            )
            assert dup_res.status_code == 409
            assert "phê duyệt" in dup_res.json()["detail"]

            # 3. Preview displays is_pending_request = True, member_count = 1
            preview_res = await ac.get(
                f"/api/v1/fandoms/{slug}",
                headers={"Authorization": f"Bearer {user_token}"},
            )
            assert preview_res.status_code == 200
            assert preview_res.json()["is_member"] is False
            assert preview_res.json()["is_pending_request"] is True
            assert preview_res.json()["member_count"] == 1

            # 4. Cancel join request via DELETE
            cancel_res = await ac.delete(
                f"/api/v1/fandoms/{slug}/join-requests/me",
                headers={"Authorization": f"Bearer {user_token}"},
            )
            assert cancel_res.status_code == 200
            assert cancel_res.json()["success"] is True

            # 5. Preview displays is_pending_request = False
            preview_after = await ac.get(
                f"/api/v1/fandoms/{slug}",
                headers={"Authorization": f"Bearer {user_token}"},
            )
            assert preview_after.json()["is_pending_request"] is False

            # 6. Canceling again yields 404
            dup_cancel = await ac.delete(
                f"/api/v1/fandoms/{slug}/join-requests/me",
                headers={"Authorization": f"Bearer {user_token}"},
            )
            assert dup_cancel.status_code == 404
    finally:
        await _cleanup_test_entities([owner_id, user_id], [fandom_id])


@pytest.mark.asyncio
async def test_owner_review_join_requests():
    """
    Test owner approving and rejecting join requests:
    - Owner can list pending requests.
    - Owner approves applicant A -> applicant A becomes ACTIVE member, member_count + 1.
    - Owner rejects applicant B -> applicant B remains non-member, member_count unchanged.
    - Non-owner cannot review requests.
    """
    suffix = uuid.uuid4().hex[:8]
    owner = User(
        username=f"owner_{suffix}",
        email=f"owner_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("Password123!"),
        display_name="Fandom Owner",
        is_active=True,
    )
    user_a = User(
        username=f"user_a_{suffix}",
        email=f"user_a_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("Password123!"),
        display_name="User A",
        is_active=True,
    )
    user_b = User(
        username=f"user_b_{suffix}",
        email=f"user_b_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("Password123!"),
        display_name="User B",
        is_active=True,
    )

    async with AsyncSessionLocal() as db:
        db.add_all([owner, user_a, user_b])
        await db.flush()

        fandom = Fandom(
            name=f"Review Fandom {suffix}",
            slug=f"review-fandom-{suffix}",
            description="Fandom duyệt đơn",
            category="Gaming / Esports",
            admission_mode="APPROVAL",
            is_public=True,
            member_count=1,
            owner_id=owner.id,
        )
        db.add(fandom)
        await db.flush()

        db.add(FandomMember(fandom_id=fandom.id, user_id=owner.id, status="ACTIVE"))
        await db.commit()

        owner_id = owner.id
        user_a_id = user_a.id
        user_b_id = user_b.id
        fandom_id = fandom.id
        slug = fandom.slug

    try:
        owner_token = create_access_token(data={"sub": str(owner_id)})
        token_a = create_access_token(data={"sub": str(user_a_id)})
        token_b = create_access_token(data={"sub": str(user_b_id)})

        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            # Both submit requests
            await ac.post(f"/api/v1/fandoms/{slug}/join", headers={"Authorization": f"Bearer {token_a}"})
            await ac.post(f"/api/v1/fandoms/{slug}/join", headers={"Authorization": f"Bearer {token_b}"})

            # Non-owner cannot list requests
            fail_list = await ac.get(f"/api/v1/fandoms/{slug}/join-requests", headers={"Authorization": f"Bearer {token_a}"})
            assert fail_list.status_code == 403

            # Owner lists requests
            reqs_res = await ac.get(f"/api/v1/fandoms/{slug}/join-requests", headers={"Authorization": f"Bearer {owner_token}"})
            assert reqs_res.status_code == 200
            requests = reqs_res.json()
            assert len(requests) == 2

            req_a = next(r for r in requests if r["user_id"] == str(user_a_id))
            req_b = next(r for r in requests if r["user_id"] == str(user_b_id))

            # Non-owner cannot review
            fail_rev = await ac.post(
                f"/api/v1/fandoms/{slug}/join-requests/{req_a['id']}/review",
                json={"action": "APPROVE"},
                headers={"Authorization": f"Bearer {token_b}"},
            )
            assert fail_rev.status_code == 403

            # Owner approves user A
            rev_a = await ac.post(
                f"/api/v1/fandoms/{slug}/join-requests/{req_a['id']}/review",
                json={"action": "APPROVE"},
                headers={"Authorization": f"Bearer {owner_token}"},
            )
            assert rev_a.status_code == 200
            assert rev_a.json()["status"] == "JOINED"

            # Owner rejects user B
            rev_b = await ac.post(
                f"/api/v1/fandoms/{slug}/join-requests/{req_b['id']}/review",
                json={"action": "REJECT"},
                headers={"Authorization": f"Bearer {owner_token}"},
            )
            assert rev_b.status_code == 200
            assert rev_b.json()["status"] == "REJECTED"

            # Check preview for User A -> member
            prev_a = await ac.get(f"/api/v1/fandoms/{slug}", headers={"Authorization": f"Bearer {token_a}"})
            assert prev_a.json()["is_member"] is True
            assert prev_a.json()["member_count"] == 2

            # Check preview for User B -> not member, not pending
            prev_b = await ac.get(f"/api/v1/fandoms/{slug}", headers={"Authorization": f"Bearer {token_b}"})
            assert prev_b.json()["is_member"] is False
            assert prev_b.json()["is_pending_request"] is False
    finally:
        await _cleanup_test_entities([owner_id, user_a_id, user_b_id], [fandom_id])


@pytest.mark.asyncio
async def test_invite_creation_and_redemption():
    """
    Test invite code creation and join-by-invite:
    - Private fandom requires invite code.
    - Owner creates invite code.
    - User redeems invite code and joins successfully.
    - Max uses limit is enforced.
    """
    suffix = uuid.uuid4().hex[:8]
    owner = User(
        username=f"owner_{suffix}",
        email=f"owner_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("Password123!"),
        display_name="Fandom Owner",
        is_active=True,
    )
    user_1 = User(
        username=f"invitee_1_{suffix}",
        email=f"invitee_1_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("Password123!"),
        display_name="Invitee 1",
        is_active=True,
    )
    user_2 = User(
        username=f"invitee_2_{suffix}",
        email=f"invitee_2_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("Password123!"),
        display_name="Invitee 2",
        is_active=True,
    )

    async with AsyncSessionLocal() as db:
        db.add_all([owner, user_1, user_2])
        await db.flush()

        fandom = Fandom(
            name=f"Private Fandom {suffix}",
            slug=f"private-fandom-{suffix}",
            description="Fandom riêng tư",
            category="Art / Design",
            admission_mode="OPEN",
            is_public=False,  # Private!
            member_count=1,
            owner_id=owner.id,
        )
        db.add(fandom)
        await db.flush()

        db.add(FandomMember(fandom_id=fandom.id, user_id=owner.id, status="ACTIVE"))
        await db.commit()

        owner_id = owner.id
        user_1_id = user_1.id
        user_2_id = user_2.id
        fandom_id = fandom.id
        slug = fandom.slug

    try:
        owner_token = create_access_token(data={"sub": str(owner_id)})
        token_1 = create_access_token(data={"sub": str(user_1_id)})
        token_2 = create_access_token(data={"sub": str(user_2_id)})

        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            # 1. Direct join without invite returns 403
            direct_res = await ac.post(f"/api/v1/fandoms/{slug}/join", headers={"Authorization": f"Bearer {token_1}"})
            assert direct_res.status_code == 403
            assert "riêng tư" in direct_res.json()["detail"]

            # 2. Owner creates invite with max_uses = 1
            inv_res = await ac.post(
                f"/api/v1/fandoms/{slug}/invites",
                json={"max_uses": 1, "expires_in_hours": 24},
                headers={"Authorization": f"Bearer {owner_token}"},
            )
            assert inv_res.status_code == 201
            invite_code = inv_res.json()["code"]

            # 3. User 1 joins via invite code
            join_inv_res = await ac.post(
                "/api/v1/fandoms/invites/join",
                json={"code": invite_code},
                headers={"Authorization": f"Bearer {token_1}"},
            )
            assert join_inv_res.status_code == 200
            assert join_inv_res.json()["status"] == "JOINED"
            assert join_inv_res.json()["slug"] == slug

            # 4. User 2 tries to use same code -> max uses exceeded (400)
            exceed_res = await ac.post(
                "/api/v1/fandoms/invites/join",
                json={"code": invite_code},
                headers={"Authorization": f"Bearer {token_2}"},
            )
            assert exceed_res.status_code == 400
            assert "đạt" in exceed_res.json()["detail"]
    finally:
        await _cleanup_test_entities([owner_id, user_1_id, user_2_id], [fandom_id])


@pytest.mark.asyncio
async def test_banned_user_blocked_from_fandom():
    """
    Test that a banned user cannot join or submit join request.
    """
    suffix = uuid.uuid4().hex[:8]
    owner = User(
        username=f"owner_{suffix}",
        email=f"owner_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("Password123!"),
        display_name="Fandom Owner",
        is_active=True,
    )
    banned_user = User(
        username=f"banned_{suffix}",
        email=f"banned_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("Password123!"),
        display_name="Banned User",
        is_active=True,
    )

    async with AsyncSessionLocal() as db:
        db.add_all([owner, banned_user])
        await db.flush()

        fandom = Fandom(
            name=f"Banned Test Fandom {suffix}",
            slug=f"banned-test-{suffix}",
            description="Testing banned restrictions",
            category="Gaming / Esports",
            admission_mode="OPEN",
            is_public=True,
            member_count=1,
            owner_id=owner.id,
        )
        db.add(fandom)
        await db.flush()

        db.add(FandomMember(fandom_id=fandom.id, user_id=owner.id, status="ACTIVE"))
        db.add(FandomMember(fandom_id=fandom.id, user_id=banned_user.id, status="BANNED"))
        await db.commit()

        owner_id = owner.id
        banned_id = banned_user.id
        fandom_id = fandom.id
        slug = fandom.slug

    try:
        banned_token = create_access_token(data={"sub": str(banned_id)})
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            res = await ac.post(f"/api/v1/fandoms/{slug}/join", headers={"Authorization": f"Bearer {banned_token}"})
            assert res.status_code == 403
            assert "bị cấm" in res.json()["detail"]
    finally:
        await _cleanup_test_entities([owner_id, banned_id], [fandom_id])


@pytest.mark.asyncio
async def test_get_my_fandoms_memberships():
    """
    Test GET /api/v1/fandoms/me/memberships:
    - User has managed fandom, joined fandom, and pending request.
    """
    suffix = uuid.uuid4().hex[:8]
    user = User(
        username=f"me_user_{suffix}",
        email=f"me_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("Password123!"),
        display_name="Me User",
        is_active=True,
    )
    other_owner = User(
        username=f"other_{suffix}",
        email=f"other_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("Password123!"),
        display_name="Other Owner",
        is_active=True,
    )

    async with AsyncSessionLocal() as db:
        db.add_all([user, other_owner])
        await db.flush()

        # Fandom 1: Managed by user
        fandom_managed = Fandom(
            name=f"Managed {suffix}",
            slug=f"managed-{suffix}",
            description="User is owner",
            category="Music / K-Pop / US-UK",
            admission_mode="OPEN",
            is_public=True,
            member_count=1,
            owner_id=user.id,
        )
        # Fandom 2: Joined by user
        fandom_joined = Fandom(
            name=f"Joined {suffix}",
            slug=f"joined-{suffix}",
            description="User is member",
            category="Anime / Manga / Cosplay",
            admission_mode="OPEN",
            is_public=True,
            member_count=2,
            owner_id=other_owner.id,
        )
        # Fandom 3: User submitted request
        fandom_pending = Fandom(
            name=f"Pending {suffix}",
            slug=f"pending-{suffix}",
            description="User is pending applicant",
            category="Gaming / Esports",
            admission_mode="APPROVAL",
            is_public=True,
            member_count=1,
            owner_id=other_owner.id,
        )
        db.add_all([fandom_managed, fandom_joined, fandom_pending])
        await db.flush()

        # Memberships
        db.add(FandomMember(fandom_id=fandom_managed.id, user_id=user.id, status="ACTIVE"))
        db.add(FandomMember(fandom_id=fandom_joined.id, user_id=other_owner.id, status="ACTIVE"))
        db.add(FandomMember(fandom_id=fandom_joined.id, user_id=user.id, status="ACTIVE"))
        db.add(FandomMember(fandom_id=fandom_pending.id, user_id=other_owner.id, status="ACTIVE"))

        # Pending request
        db.add(FandomJoinRequest(fandom_id=fandom_pending.id, user_id=user.id, status="PENDING"))
        await db.commit()

        user_id = user.id
        other_owner_id = other_owner.id
        fandom_ids = [fandom_managed.id, fandom_joined.id, fandom_pending.id]

    try:
        user_token = create_access_token(data={"sub": str(user_id)})
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            res = await ac.get("/api/v1/fandoms/me/memberships", headers={"Authorization": f"Bearer {user_token}"})
            assert res.status_code == 200
            data = res.json()
            assert any(f["id"] == str(fandom_managed.id) for f in data["managed"])
            assert any(f["id"] == str(fandom_joined.id) for f in data["joined"])
            assert any(r["fandom_id"] == str(fandom_pending.id) for r in data["pending_requests"])
    finally:
        await _cleanup_test_entities([user_id, other_owner_id], fandom_ids)


@pytest.mark.asyncio
async def test_action_rate_limiting():
    """
    Test rate limit on user actions per fandom:
    - Max 5 join/leave/cancel actions within 60 seconds.
    - 6th action returns 429 Too Many Requests.
    """
    suffix = uuid.uuid4().hex[:8]
    owner = User(
        username=f"owner_{suffix}",
        email=f"owner_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("Password123!"),
        display_name="Fandom Owner",
        is_active=True,
    )
    user = User(
        username=f"spammer_{suffix}",
        email=f"spammer_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("Password123!"),
        display_name="Spam User",
        is_active=True,
    )

    async with AsyncSessionLocal() as db:
        db.add_all([owner, user])
        await db.flush()

        fandom = Fandom(
            name=f"Rate Limit Fandom {suffix}",
            slug=f"rate-limit-{suffix}",
            description="Testing rate limiting",
            category="Music / K-Pop / US-UK",
            admission_mode="OPEN",
            is_public=True,
            member_count=1,
            owner_id=owner.id,
        )
        db.add(fandom)
        await db.flush()

        db.add(FandomMember(fandom_id=fandom.id, user_id=owner.id, status="ACTIVE"))
        await db.commit()

        owner_id = owner.id
        user_id = user.id
        fandom_id = fandom.id
        slug = fandom.slug

    try:
        user_token = create_access_token(data={"sub": str(user_id)})
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            # Action 1: Join
            r1 = await ac.post(f"/api/v1/fandoms/{slug}/join", headers={"Authorization": f"Bearer {user_token}"})
            assert r1.status_code == 200

            # Action 2: Leave
            r2 = await ac.post(f"/api/v1/fandoms/{slug}/leave", headers={"Authorization": f"Bearer {user_token}"})
            assert r2.status_code == 200

            # Action 3: Join
            r3 = await ac.post(f"/api/v1/fandoms/{slug}/join", headers={"Authorization": f"Bearer {user_token}"})
            assert r3.status_code == 200

            # Action 4: Leave
            r4 = await ac.post(f"/api/v1/fandoms/{slug}/leave", headers={"Authorization": f"Bearer {user_token}"})
            assert r4.status_code == 200

            # Action 5: Join
            r5 = await ac.post(f"/api/v1/fandoms/{slug}/join", headers={"Authorization": f"Bearer {user_token}"})
            assert r5.status_code == 200

            # Action 6: 429 Too Many Requests
            r6 = await ac.post(f"/api/v1/fandoms/{slug}/leave", headers={"Authorization": f"Bearer {user_token}"})
            assert r6.status_code == 429
            assert "nhanh" in r6.json()["detail"]
    finally:
        await _cleanup_test_entities([owner_id, user_id], [fandom_id])


@pytest.mark.asyncio
async def test_invite_bruteforce_and_expiry():
    """
    Test invite code brute-force protection (429) and expired invite (400).
    """
    suffix = uuid.uuid4().hex[:8]
    owner = User(
        username=f"owner_{suffix}",
        email=f"owner_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("Password123!"),
        display_name="Fandom Owner",
        is_active=True,
    )
    user = User(
        username=f"attacker_{suffix}",
        email=f"attacker_{suffix}@test.fanspace.vn",
        password_hash=get_password_hash("Password123!"),
        display_name="Attacker",
        is_active=True,
    )

    async with AsyncSessionLocal() as db:
        db.add_all([owner, user])
        await db.flush()

        fandom = Fandom(
            name=f"Invite Sec Fandom {suffix}",
            slug=f"invite-sec-{suffix}",
            description="Testing invite protections",
            category="Music / K-Pop / US-UK",
            admission_mode="OPEN",
            is_public=False,
            member_count=1,
            owner_id=owner.id,
        )
        db.add(fandom)
        await db.flush()

        db.add(FandomMember(fandom_id=fandom.id, user_id=owner.id, status="ACTIVE"))

        # Add an expired invite
        expired_invite = FandomInvite(
            fandom_id=fandom.id,
            code="EXPIRED1",
            max_uses=10,
            uses_count=0,
            expires_at=datetime.now(timezone.utc) - timedelta(hours=1),
            created_by=owner.id,
        )
        db.add(expired_invite)
        await db.commit()

        owner_id = owner.id
        user_id = user.id
        fandom_id = fandom.id

    try:
        user_token = create_access_token(data={"sub": str(user_id)})
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            # 1. Expired invite returns 400
            exp_res = await ac.post(
                "/api/v1/fandoms/invites/join",
                json={"code": "EXPIRED1"},
                headers={"Authorization": f"Bearer {user_token}"},
            )
            assert exp_res.status_code == 400
            assert "hết" in exp_res.json()["detail"]

            # 2. Brute-force invalid invite codes up to limit
            for i in range(9):
                res = await ac.post(
                    "/api/v1/fandoms/invites/join",
                    json={"code": f"FAKE{i}123"},
                    headers={"Authorization": f"Bearer {user_token}"},
                )
                assert res.status_code == 404

            # 11th total attempt hits 429
            brute_res = await ac.post(
                "/api/v1/fandoms/invites/join",
                json={"code": "FAKEMORE"},
                headers={"Authorization": f"Bearer {user_token}"},
            )
            assert brute_res.status_code == 429
            assert "nhiều lần" in brute_res.json()["detail"]
    finally:
        await _cleanup_test_entities([owner_id, user_id], [fandom_id])

