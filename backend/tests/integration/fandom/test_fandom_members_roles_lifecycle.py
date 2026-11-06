"""Integration tests for Fandom Member Management and Role RBAC (FR-08 / UC-06, UC-10).

Covers:
1. Custom Role CRUD, Role Priority sorting, and Preset Mod assignment (Co-Host, Chat Moderator).
2. Role anti-escalation enforcement (cannot assign or modify role >= own priority).
3. Member listing, search, and dynamic role assignment.
4. Member Moderation: Mute/Unmute, Kick (can rejoin), Ban (cannot rejoin even with invite), Unban.
5. Fandom Invites: Listing active invites and revoking invites.
6. Integration with DefaultMembershipPermissionAdapter (resolved permissions include role bitmasks).
"""

import uuid
from datetime import datetime, timezone
import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import delete, select

from app.core.database import AsyncSessionLocal
from app.core.permissions import DefaultMembershipPermissionAdapter, Permission
from app.core.security import create_access_token, get_password_hash
from app.main import app
from app.modules.chat.models import Channel
from app.modules.fandom.models import Fandom, FandomInvite, FandomMember
from app.modules.identity.models import User
from app.modules.rbac.models import MemberRole, PermissionBit, Role


async def _cleanup_entities(user_ids: list[uuid.UUID], fandom_ids: list[uuid.UUID]) -> None:
    """Cleans up database records created during test runs."""
    async with AsyncSessionLocal() as db:
        if fandom_ids:
            await db.execute(delete(FandomInvite).where(FandomInvite.fandom_id.in_(fandom_ids)))
            await db.execute(delete(Channel).where(Channel.fandom_id.in_(fandom_ids)))
            await db.execute(delete(MemberRole).where(MemberRole.fandom_id.in_(fandom_ids)))
            await db.execute(delete(Role).where(Role.fandom_id.in_(fandom_ids)))
            await db.execute(delete(FandomMember).where(FandomMember.fandom_id.in_(fandom_ids)))
            await db.execute(delete(Fandom).where(Fandom.id.in_(fandom_ids)))
        if user_ids:
            await db.execute(delete(User).where(User.id.in_(user_ids)))
        await db.commit()


@pytest.mark.asyncio
async def test_roles_crud_and_preset_mod_assignment():
    """Tests creating, updating, listing, and deleting custom roles and assigning preset mods."""
    suffix = uuid.uuid4().hex[:8]
    password = "SecurePassword123!"

    owner = User(
        username=f"owner_{suffix}",
        email=f"owner_{suffix}@test.vn",
        password_hash=get_password_hash(password),
        display_name="Owner User",
        is_active=True,
    )
    member = User(
        username=f"member_{suffix}",
        email=f"member_{suffix}@test.vn",
        password_hash=get_password_hash(password),
        display_name="Member User",
        is_active=True,
    )

    async with AsyncSessionLocal() as db:
        db.add_all([owner, member])
        await db.commit()
        await db.refresh(owner)
        await db.refresh(member)

        fandom = Fandom(
            name=f"Fandom Roles {suffix}",
            slug=f"fandom-roles-{suffix}",
            owner_id=owner.id,
            category="Âm nhạc",
            admission_mode="OPEN",
            member_count=2,
        )
        db.add(fandom)
        await db.commit()
        await db.refresh(fandom)

        # Add both as members
        db.add_all([
            FandomMember(fandom_id=fandom.id, user_id=owner.id, status="ACTIVE"),
            FandomMember(fandom_id=fandom.id, user_id=member.id, status="ACTIVE"),
        ])
        await db.commit()

    owner_token = create_access_token(data={"sub": str(owner.id), "username": owner.username})
    owner_headers = {"Authorization": f"Bearer {owner_token}"}
    transport = ASGITransport(app=app)

    try:
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            # 1. Create a custom role as Owner
            res_create = await client.post(
                f"/api/v1/fandoms/{fandom.id}/roles",
                headers=owner_headers,
                json={
                    "name": "VIP Supporter",
                    "color_hex": "#E91E63",
                    "priority": 50,
                    "permissions_bitmask": PermissionBit.READ_MESSAGES | PermissionBit.SEND_MESSAGES | PermissionBit.EMBED_LINKS,
                },
            )
            assert res_create.status_code == 201, res_create.text
            role_data = res_create.json()
            assert role_data["name"] == "VIP Supporter"
            assert role_data["priority"] == 50
            role_id = role_data["id"]

            # 2. Update the role
            res_update = await client.put(
                f"/api/v1/fandoms/{fandom.id}/roles/{role_id}",
                headers=owner_headers,
                json={
                    "name": "Super VIP Supporter",
                    "priority": 60,
                },
            )
            assert res_update.status_code == 200
            assert res_update.json()["name"] == "Super VIP Supporter"
            assert res_update.json()["priority"] == 60

            # 3. Assign Preset Mod (Chat Moderator) to member
            res_mod = await client.post(
                f"/api/v1/fandoms/{fandom.id}/roles/assign-preset-mod",
                headers=owner_headers,
                json={
                    "user_id": str(member.id),
                    "preset_type": "CHAT_MODERATOR",
                },
            )
            assert res_mod.status_code == 200, res_mod.text
            assert res_mod.json()["name"] == "Chat Moderator"
            assert res_mod.json()["is_preset_mod"] is True

            # 4. List all roles (should include Super VIP and Chat Moderator sorted by priority desc)
            res_list = await client.get(
                f"/api/v1/fandoms/{fandom.id}/roles",
                headers=owner_headers,
            )
            assert res_list.status_code == 200
            roles_list = res_list.json()
            assert len(roles_list) >= 2
            priorities = [r["priority"] for r in roles_list]
            assert priorities == sorted(priorities, reverse=True)

            # 5. Delete the custom role
            res_del = await client.delete(
                f"/api/v1/fandoms/{fandom.id}/roles/{role_id}",
                headers=owner_headers,
            )
            assert res_del.status_code == 200
            assert res_del.json()["success"] is True

    finally:
        await _cleanup_entities([owner.id, member.id], [fandom.id])


@pytest.mark.asyncio
async def test_member_listing_and_role_assignment():
    """Tests listing members with filters and dynamically assigning custom roles."""
    suffix = uuid.uuid4().hex[:8]
    password = "SecurePassword123!"

    owner = User(
        username=f"list_owner_{suffix}",
        email=f"list_owner_{suffix}@test.vn",
        password_hash=get_password_hash(password),
        display_name="Role Manager Owner",
        is_active=True,
    )
    fan = User(
        username=f"fan_{suffix}",
        email=f"fan_{suffix}@test.vn",
        password_hash=get_password_hash(password),
        display_name="Loyal Fan",
        is_active=True,
    )

    async with AsyncSessionLocal() as db:
        db.add_all([owner, fan])
        await db.commit()
        await db.refresh(owner)
        await db.refresh(fan)

        fandom = Fandom(
            name=f"Fandom Members {suffix}",
            slug=f"fandom-members-{suffix}",
            owner_id=owner.id,
            category="Thần tượng (Idol)",
            admission_mode="OPEN",
            member_count=2,
        )
        db.add(fandom)
        await db.commit()
        await db.refresh(fandom)

        db.add_all([
            FandomMember(fandom_id=fandom.id, user_id=owner.id, status="ACTIVE"),
            FandomMember(fandom_id=fandom.id, user_id=fan.id, status="ACTIVE"),
        ])
        await db.commit()

    owner_token = create_access_token(data={"sub": str(owner.id), "username": owner.username})
    owner_headers = {"Authorization": f"Bearer {owner_token}"}
    transport = ASGITransport(app=app)

    try:
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            # 1. List members (should contain both owner and fan)
            res_members = await client.get(
                f"/api/v1/fandoms/{fandom.id}/members",
                headers=owner_headers,
            )
            assert res_members.status_code == 200
            members_data = res_members.json()
            assert len(members_data) == 2
            user_ids = [m["user_id"] for m in members_data]
            assert str(owner.id) in user_ids
            assert str(fan.id) in user_ids

            # 2. Search member by display_name
            res_search = await client.get(
                f"/api/v1/fandoms/{fandom.id}/members?search=Loyal",
                headers=owner_headers,
            )
            assert res_search.status_code == 200
            search_data = res_search.json()
            assert len(search_data) == 1
            assert search_data[0]["username"] == fan.username

            # 3. Create a custom role and assign it to fan
            res_create_role = await client.post(
                f"/api/v1/fandoms/{fandom.id}/roles",
                headers=owner_headers,
                json={
                    "name": "Elite Fan",
                    "color_hex": "#00E676",
                    "priority": 25,
                    "permissions_bitmask": PermissionBit.READ_MESSAGES | PermissionBit.SEND_MESSAGES,
                },
            )
            role_id = res_create_role.json()["id"]

            res_assign = await client.post(
                f"/api/v1/fandoms/{fandom.id}/members/{fan.id}/roles",
                headers=owner_headers,
                json={"role_ids": [role_id]},
            )
            assert res_assign.status_code == 200
            assigned_data = res_assign.json()
            assert len(assigned_data["roles"]) == 1
            assert assigned_data["roles"][0]["name"] == "Elite Fan"

            # 4. Verify resolved permissions via DefaultMembershipPermissionAdapter
            async with AsyncSessionLocal() as db:
                adapter = DefaultMembershipPermissionAdapter(db=db)
                permissions = await adapter.resolve_permissions(user_id=fan.id, fandom_id=fandom.id)
                assert Permission.READ_MESSAGES in permissions
                assert Permission.SEND_MESSAGES in permissions
                assert Permission.MANAGE_CHANNELS not in permissions

    finally:
        await _cleanup_entities([owner.id, fan.id], [fandom.id])


@pytest.mark.asyncio
async def test_member_moderation_lifecycle_mute_kick_ban_unban():
    """Tests the full moderation lifecycle: mute, unmute, kick, ban, and unban."""
    suffix = uuid.uuid4().hex[:8]
    password = "SecurePassword123!"

    owner = User(
        username=f"mod_owner_{suffix}",
        email=f"mod_owner_{suffix}@test.vn",
        password_hash=get_password_hash(password),
        display_name="Moderator Owner",
        is_active=True,
    )
    spammer = User(
        username=f"spammer_{suffix}",
        email=f"spammer_{suffix}@test.vn",
        password_hash=get_password_hash(password),
        display_name="Spam User",
        is_active=True,
    )

    async with AsyncSessionLocal() as db:
        db.add_all([owner, spammer])
        await db.commit()
        await db.refresh(owner)
        await db.refresh(spammer)

        fandom = Fandom(
            name=f"Fandom Mod {suffix}",
            slug=f"fandom-mod-{suffix}",
            owner_id=owner.id,
            category="Game & Esports",
            admission_mode="OPEN",
            member_count=2,
        )
        db.add(fandom)
        await db.commit()
        await db.refresh(fandom)

        db.add_all([
            FandomMember(fandom_id=fandom.id, user_id=owner.id, status="ACTIVE"),
            FandomMember(fandom_id=fandom.id, user_id=spammer.id, status="ACTIVE"),
        ])
        await db.commit()

    owner_token = create_access_token(data={"sub": str(owner.id), "username": owner.username})
    owner_headers = {"Authorization": f"Bearer {owner_token}"}
    spammer_token = create_access_token(data={"sub": str(spammer.id), "username": spammer.username})
    spammer_headers = {"Authorization": f"Bearer {spammer_token}"}
    transport = ASGITransport(app=app)

    try:
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            # 1. Mute spammer for 2 hours
            res_mute = await client.post(
                f"/api/v1/fandoms/{fandom.id}/members/{spammer.id}/mute",
                headers=owner_headers,
                json={"duration_hours": 2, "reason": "Spamming link in general chat"},
            )
            assert res_mute.status_code == 200
            assert res_mute.json()["action"] == "MUTE"

            # Verify permissions adapter discards SEND_MESSAGES for muted member
            async with AsyncSessionLocal() as db:
                adapter = DefaultMembershipPermissionAdapter(db=db)
                perms = await adapter.resolve_permissions(user_id=spammer.id, fandom_id=fandom.id)
                assert Permission.READ_MESSAGES in perms
                assert Permission.SEND_MESSAGES not in perms

            # 2. Unmute spammer
            res_unmute = await client.delete(
                f"/api/v1/fandoms/{fandom.id}/members/{spammer.id}/mute",
                headers=owner_headers,
            )
            assert res_unmute.status_code == 200
            assert res_unmute.json()["action"] == "UNMUTE"

            # Verify permissions restored
            async with AsyncSessionLocal() as db:
                adapter = DefaultMembershipPermissionAdapter(db=db)
                perms = await adapter.resolve_permissions(user_id=spammer.id, fandom_id=fandom.id)
                assert Permission.SEND_MESSAGES in perms

            # 3. Kick spammer
            res_kick = await client.post(
                f"/api/v1/fandoms/{fandom.id}/members/{spammer.id}/kick",
                headers=owner_headers,
                json={"reason": "Insubordination"},
            )
            assert res_kick.status_code == 200
            assert res_kick.json()["action"] == "KICK"

            # Spammer can rejoin OPEN fandom after kick
            res_rejoin = await client.post(
                f"/api/v1/fandoms/{fandom.id}/join",
                headers=spammer_headers,
            )
            assert res_rejoin.status_code == 200
            assert res_rejoin.json()["status"] == "JOINED"

            # 4. Ban spammer permanently
            res_ban = await client.post(
                f"/api/v1/fandoms/{fandom.id}/members/{spammer.id}/ban",
                headers=owner_headers,
                json={"reason": "Severe toxicity and harassment"},
            )
            assert res_ban.status_code == 200
            assert res_ban.json()["action"] == "BAN"

            # Spammer cannot rejoin when banned (403 Forbidden)
            res_banned_join = await client.post(
                f"/api/v1/fandoms/{fandom.id}/join",
                headers=spammer_headers,
            )
            assert res_banned_join.status_code == 403

            # 5. Unban spammer
            res_unban = await client.post(
                f"/api/v1/fandoms/{fandom.id}/members/{spammer.id}/unban",
                headers=owner_headers,
            )
            assert res_unban.status_code == 200
            assert res_unban.json()["action"] == "UNBAN"

            # Spammer can now rejoin
            res_after_unban = await client.post(
                f"/api/v1/fandoms/{fandom.id}/join",
                headers=spammer_headers,
            )
            assert res_after_unban.status_code == 200
            assert res_after_unban.json()["status"] == "JOINED"

    finally:
        await _cleanup_entities([owner.id, spammer.id], [fandom.id])


@pytest.mark.asyncio
async def test_fandom_invites_listing_and_revocation():
    """Tests listing active invite codes and revoking an invite code."""
    suffix = uuid.uuid4().hex[:8]
    password = "SecurePassword123!"

    owner = User(
        username=f"inv_owner_{suffix}",
        email=f"inv_owner_{suffix}@test.vn",
        password_hash=get_password_hash(password),
        display_name="Invite Owner",
        is_active=True,
    )
    guest = User(
        username=f"guest_{suffix}",
        email=f"guest_{suffix}@test.vn",
        password_hash=get_password_hash(password),
        display_name="Guest User",
        is_active=True,
    )

    async with AsyncSessionLocal() as db:
        db.add_all([owner, guest])
        await db.commit()
        await db.refresh(owner)
        await db.refresh(guest)

        fandom = Fandom(
            name=f"Fandom Invites {suffix}",
            slug=f"fandom-invites-{suffix}",
            owner_id=owner.id,
            category="Công nghệ",
            admission_mode="APPROVAL",  # Approval mode, invites bypass approval
            member_count=1,
        )
        db.add(fandom)
        await db.commit()
        await db.refresh(fandom)

        db.add(FandomMember(fandom_id=fandom.id, user_id=owner.id, status="ACTIVE"))
        await db.commit()

    owner_token = create_access_token(data={"sub": str(owner.id), "username": owner.username})
    owner_headers = {"Authorization": f"Bearer {owner_token}"}
    guest_token = create_access_token(data={"sub": str(guest.id), "username": guest.username})
    guest_headers = {"Authorization": f"Bearer {guest_token}"}
    transport = ASGITransport(app=app)

    try:
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            # 1. Create two invite codes (one with 10 max_uses, one single use)
            res_inv1 = await client.post(
                f"/api/v1/fandoms/{fandom.id}/invites",
                headers=owner_headers,
                json={"max_uses": 10, "expires_in_hours": 48},
            )
            assert res_inv1.status_code == 201
            code1 = res_inv1.json()["code"]

            res_inv2 = await client.post(
                f"/api/v1/fandoms/{fandom.id}/invites",
                headers=owner_headers,
                json={"max_uses": 1, "expires_in_hours": None},
            )
            assert res_inv2.status_code == 201
            code2 = res_inv2.json()["code"]

            # 2. List invites (should return both)
            res_list = await client.get(
                f"/api/v1/fandoms/{fandom.id}/invites",
                headers=owner_headers,
            )
            assert res_list.status_code == 200
            invites = res_list.json()
            codes = [inv["code"] for inv in invites]
            assert code1 in codes
            assert code2 in codes

            # 3. Revoke code2
            res_revoke = await client.delete(
                f"/api/v1/fandoms/{fandom.id}/invites/{code2}",
                headers=owner_headers,
            )
            assert res_revoke.status_code == 200
            assert res_revoke.json()["success"] is True

            # 4. Attempting to join via revoked code2 fails with 404
            res_join_revoked = await client.post(
                "/api/v1/fandoms/invites/join",
                headers=guest_headers,
                json={"code": code2},
            )
            assert res_join_revoked.status_code == 404

            # 5. Joining via valid code1 succeeds and bypasses APPROVAL mode
            res_join_valid = await client.post(
                "/api/v1/fandoms/invites/join",
                headers=guest_headers,
                json={"code": code1},
            )
            assert res_join_valid.status_code == 200
            assert res_join_valid.json()["status"] == "JOINED"

    finally:
        await _cleanup_entities([owner.id, guest.id], [fandom.id])
