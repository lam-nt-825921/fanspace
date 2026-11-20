"""Real-time Voice Channel Service and Agora Dynamic RTC Token Builder (FR-11 / UC-06).

Implements:
- `AgoraTokenBuilder`: Cryptographic HMAC-SHA256 Agora RTC `006` Dynamic Token generator.
- `VoiceChannelService`: Redis-backed real-time voice room state management supporting:
  - `OPEN_MIC` and `STAGE_ROOM` voice channel modes
  - `max_members` concurrent room capacity enforcement
  - Dynamic RTC Token generation (`POST /api/v1/channels/{channel_id}/voice/token`)
  - Room state inspection (`GET /api/v1/channels/{channel_id}/voice/state`)
  - Stage Room Raise Hand toggle (`POST /api/v1/channels/{channel_id}/voice/raise-hand`)
  - Moderator speaker promotion/demotion & mute (`PUT /api/v1/channels/{channel_id}/voice/speakers/{user_id}`)
  - Participant self mute/unmute (`PUT /api/v1/channels/{channel_id}/voice/me/mute`)
  - Host/Moderator Mute All (`POST /api/v1/channels/{channel_id}/voice/mute-all`)
  - Leaving voice room (`POST /api/v1/channels/{channel_id}/voice/leave`)
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import secrets
import struct
import time
import uuid
import zlib
from datetime import datetime, timezone

import redis.asyncio as aioredis
from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.permissions import IPermissionChecker, Permission, PermissionSpec
from app.modules.chat.models import Channel
from app.modules.chat.schemas import (
    VoiceParticipantOut,
    VoiceParticipantRole,
    VoiceRaiseHandRequest,
    VoiceRoomStateOut,
    VoiceSelfMuteRequest,
    VoiceSpeakerManageRequest,
    VoiceTokenOut,
)
from app.modules.chat.service import MessageService
from app.modules.fandom.models import Fandom
from app.modules.identity.models import User

VOICE_CONNECT_SPEC = PermissionSpec.of(
    must_have={Permission.VIEW_CHANNEL, Permission.VOICE_CONNECT},
    may_have={
        Permission.VOICE_SPEAK,
        Permission.MODERATE_CHAT,
        Permission.MANAGE_CHANNELS,
    },
)

VOICE_MODERATE_SPEC = PermissionSpec.of(
    must_have={Permission.VIEW_CHANNEL},
    any_of={Permission.MODERATE_CHAT, Permission.MANAGE_CHANNELS},
)


class AgoraTokenBuilder:
    """Cryptographic Agora Dynamic RTC Token (`006`) generator using HMAC-SHA256."""

    VERSION = "006"
    PRIVILEGE_JOIN_CHANNEL = 1
    PRIVILEGE_PUBLISH_AUDIO = 2
    PRIVILEGE_PUBLISH_VIDEO = 3
    PRIVILEGE_PUBLISH_DATA_STREAM = 4

    @classmethod
    def build_rtc_token(
        cls,
        app_id: str,
        app_certificate: str,
        channel_name: str,
        uid: int,
        role: str = "PUBLISHER",
        expire_seconds: int = 3600,
    ) -> str:
        """Builds a signed Agora `006` Dynamic RTC Token.

        Args:
            app_id: 32-character Agora App ID.
            app_certificate: 32-character Agora App Certificate secret.
            channel_name: Target Agora channel room identifier.
            uid: 32-bit unsigned integer participant UID.
            role: 'PUBLISHER' (can transmit audio) or 'SUBSCRIBER' (listener only).
            expire_seconds: Token validity duration in seconds.

        Returns:
            str: Base64-encoded Agora `006` Dynamic RTC Token string.
        """
        cfg = get_settings()
        clean_app_id = (app_id or cfg.AGORA_APP_ID).strip()
        clean_cert = (app_certificate or cfg.AGORA_APP_CERTIFICATE).strip()
        now_ts = int(time.time())
        expire_ts = now_ts + max(60, expire_seconds)
        salt = secrets.randbelow(99999999) + 1
        uid_str = "" if uid == 0 else str(uid)

        privileges: dict[int, int] = {
            cls.PRIVILEGE_JOIN_CHANNEL: expire_ts,
        }
        if role.upper() in ("PUBLISHER", "SPEAKER"):
            privileges[cls.PRIVILEGE_PUBLISH_AUDIO] = expire_ts
            privileges[cls.PRIVILEGE_PUBLISH_VIDEO] = expire_ts
            privileges[cls.PRIVILEGE_PUBLISH_DATA_STREAM] = expire_ts

        # Pack message: salt (uint32) + ts (uint32) + privileges map
        msg_buf = struct.pack("<IIH", salt, expire_ts, len(privileges))
        for k, v in sorted(privileges.items()):
            msg_buf += struct.pack("<HI", k, v)

        sign_target = (
            clean_app_id.encode("utf-8")
            + channel_name.encode("utf-8")
            + uid_str.encode("utf-8")
            + msg_buf
        )
        signature = hmac.new(
            clean_cert.encode("utf-8"),
            sign_target,
            hashlib.sha256,
        ).digest()

        crc_channel = zlib.crc32(channel_name.encode("utf-8")) & 0xFFFFFFFF
        crc_uid = zlib.crc32(uid_str.encode("utf-8")) & 0xFFFFFFFF

        content = (
            struct.pack("<H", len(signature))
            + signature
            + struct.pack("<IIH", crc_channel, crc_uid, len(msg_buf))
            + msg_buf
        )
        encoded = base64.b64encode(content).decode("utf-8")
        return f"{cls.VERSION}{clean_app_id}{encoded}"


class VoiceChannelService:
    """Service managing real-time Agora RTC Voice Rooms and Stage Room moderation."""

    ROOM_TTL_SECONDS = 7200

    @staticmethod
    def uuid_to_agora_uid(user_id: uuid.UUID) -> int:
        """Deterministically maps a User UUID to a positive 31-bit integer Agora UID."""
        raw = user_id.int & 0x7FFFFFFF
        return raw if raw > 0 else 1

    @staticmethod
    def _participants_key(channel_id: uuid.UUID) -> str:
        return f"voice:room:{channel_id}:participants"

    @staticmethod
    def _raised_hands_key(channel_id: uuid.UUID) -> str:
        return f"voice:room:{channel_id}:raised_hands"

    @staticmethod
    def _active_members_key(channel_id: uuid.UUID) -> str:
        return f"channel:active_members:{channel_id}"

    @classmethod
    async def _resolve_voice_channel(
        cls,
        db: AsyncSession,
        channel_id: uuid.UUID,
    ) -> tuple[Channel, Fandom]:
        """Resolves a Channel and verifies that it is of type `VOICE`."""
        channel, fandom = await MessageService.resolve_channel_and_fandom(db, channel_id)
        if channel.type != "VOICE":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Kênh này không phải là Kênh Thoại (VOICE).",
            )
        return channel, fandom

    @classmethod
    async def _build_room_state(
        cls,
        channel: Channel,
        fandom: Fandom,
        redis: aioredis.Redis,
    ) -> VoiceRoomStateOut:
        """Loads and serializes the current voice room state from Redis."""
        p_key = cls._participants_key(channel.id)
        h_key = cls._raised_hands_key(channel.id)

        raw_map = await redis.hgetall(p_key)
        raw_hands = await redis.smembers(h_key)
        raised_set = {
            (h.decode("utf-8") if isinstance(h, bytes) else str(h))
            for h in (raw_hands or set())
        }

        participants: list[VoiceParticipantOut] = []
        for k, v in (raw_map or {}).items():
            try:
                text_val = v.decode("utf-8") if isinstance(v, bytes) else str(v)
                data = json.loads(text_val)
                uid_str = str(data["user_id"])
                is_raised = uid_str in raised_set or bool(data.get("is_hand_raised", False))
                parsed_uid = uuid.UUID(uid_str)
                participants.append(
                    VoiceParticipantOut(
                        user_id=parsed_uid,
                        agora_uid=cls.uuid_to_agora_uid(parsed_uid),
                        username=data.get("username", ""),
                        display_name=data.get("display_name", ""),
                        avatar_url=data.get("avatar_url"),
                        role=data.get("role", "LISTENER"),
                        is_muted=bool(data.get("is_muted", True)),
                        is_hand_raised=is_raised,
                        is_owner=(uuid.UUID(uid_str) == fandom.owner_id),
                        joined_at=datetime.fromisoformat(data["joined_at"]),
                    )
                )
            except Exception:
                continue

        # Sort speakers first, then owner, then by join time
        participants.sort(
            key=lambda p: (
                0 if p.role == "SPEAKER" else 1,
                0 if p.is_owner else 1,
                p.joined_at,
            )
        )
        active_ids = {str(p.user_id) for p in participants}
        valid_raised_hands = sorted(uid for uid in raised_set if uid in active_ids)

        return VoiceRoomStateOut(
            channel_id=channel.id,
            fandom_id=fandom.id,
            channel_name=channel.name,
            voice_room_type=channel.voice_room_type or "OPEN_MIC",
            max_members=int(getattr(channel, "max_members", 0) or 0),
            active_count=len(participants),
            participants=participants,
            raised_hand_user_ids=valid_raised_hands,
        )

    @classmethod
    async def _broadcast_room_state(
        cls,
        channel_id: uuid.UUID,
        state: VoiceRoomStateOut,
    ) -> None:
        """Broadcasts `voice_state_updated` to all connected Socket.IO clients in the channel."""
        try:
            from app.main import sio

            await sio.emit(
                "voice_state_updated",
                state.model_dump(mode="json"),
                room=f"channel:{channel_id}",
            )
        except Exception:
            pass

    @classmethod
    async def issue_voice_token_and_join(
        cls,
        db: AsyncSession,
        channel_id: uuid.UUID,
        current_user: User,
        perm_checker: IPermissionChecker,
        redis: aioredis.Redis,
    ) -> VoiceTokenOut:
        """Verifies VOICE_CONNECT & max_members capacity, registers user in room, and issues Agora RTC Token."""
        channel, fandom = await cls._resolve_voice_channel(db, channel_id)
        eval_ctx = await perm_checker.verify(
            user_id=current_user.id,
            fandom_id=fandom.id,
            channel_id=channel.id,
            spec=VOICE_CONNECT_SPEC,
            error_detail="Bạn không có quyền kết nối vào phòng thoại này.",
        )

        p_key = cls._participants_key(channel.id)
        active_key = cls._active_members_key(channel.id)
        user_id_str = str(current_user.id)

        already_in_room = await redis.hexists(p_key, user_id_str)
        current_count = int(await redis.hlen(p_key) or 0)
        max_members = int(getattr(channel, "max_members", 0) or 0)

        if (
            max_members > 0
            and not already_in_room
            and current_count >= max_members
            and not eval_ctx.has(Permission.MANAGE_CHANNELS)
        ):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Phòng thoại đã đạt giới hạn tối đa {max_members} người tham gia đồng thời.",
            )

        is_stage = (channel.voice_room_type or "OPEN_MIC") == "STAGE_ROOM"
        can_speak_by_default = eval_ctx.has(Permission.VOICE_SPEAK)
        is_mod_or_owner = (
            current_user.id == fandom.owner_id
            or eval_ctx.has(Permission.MODERATE_CHAT)
            or eval_ctx.has(Permission.MANAGE_CHANNELS)
        )

        if is_stage:
            initial_role: VoiceParticipantRole = (
                "SPEAKER" if (is_mod_or_owner or can_speak_by_default) else "LISTENER"
            )
        else:
            initial_role = "SPEAKER" if can_speak_by_default else "LISTENER"

        # Preserve existing speaker promotion if re-fetching token while already in room
        if already_in_room:
            raw_existing = await redis.hget(p_key, user_id_str)
            if raw_existing:
                try:
                    existing_data = json.loads(
                        raw_existing.decode("utf-8")
                        if isinstance(raw_existing, bytes)
                        else str(raw_existing)
                    )
                    if existing_data.get("role") == "SPEAKER":
                        initial_role = "SPEAKER"
                except Exception:
                    pass

        participant_payload = {
            "user_id": user_id_str,
            "username": current_user.username,
            "display_name": current_user.display_name or current_user.username,
            "avatar_url": current_user.avatar_url,
            "role": initial_role,
            "is_muted": False if (initial_role == "SPEAKER" and not is_stage) else True,
            "is_hand_raised": False,
            "joined_at": datetime.now(timezone.utc).isoformat(),
        }
        await redis.hset(p_key, user_id_str, json.dumps(participant_payload))
        await redis.expire(p_key, cls.ROOM_TTL_SECONDS)
        await redis.sadd(active_key, user_id_str)
        await redis.expire(active_key, cls.ROOM_TTL_SECONDS)

        settings = get_settings()
        agora_uid = cls.uuid_to_agora_uid(current_user.id)
        agora_channel_name = f"fanspace_voice_{channel.id.hex}"
        can_publish = initial_role == "SPEAKER"
        rtc_token = AgoraTokenBuilder.build_rtc_token(
            app_id=settings.AGORA_APP_ID,
            app_certificate=settings.AGORA_APP_CERTIFICATE,
            channel_name=agora_channel_name,
            uid=agora_uid,
            role="PUBLISHER" if can_publish else "SUBSCRIBER",
            expire_seconds=settings.AGORA_TOKEN_TTL_SECONDS,
        )

        room_state = await cls._build_room_state(channel, fandom, redis)
        await cls._broadcast_room_state(channel.id, room_state)

        return VoiceTokenOut(
            app_id=settings.AGORA_APP_ID,
            channel_name=agora_channel_name,
            rtc_token=rtc_token,
            uid=agora_uid,
            role=initial_role,
            can_publish=can_publish,
            expires_in=settings.AGORA_TOKEN_TTL_SECONDS,
            room_state=room_state,
        )

    @classmethod
    async def get_voice_room_state(
        cls,
        db: AsyncSession,
        channel_id: uuid.UUID,
        current_user: User,
        perm_checker: IPermissionChecker,
        redis: aioredis.Redis,
    ) -> VoiceRoomStateOut:
        """Returns the current state of participants and raised hands in a voice room."""
        channel, fandom = await cls._resolve_voice_channel(db, channel_id)
        await perm_checker.verify(
            user_id=current_user.id,
            fandom_id=fandom.id,
            channel_id=channel.id,
            spec=PermissionSpec.of(must_have={Permission.VIEW_CHANNEL}),
            error_detail="Bạn không có quyền xem trạng thái phòng thoại này.",
        )
        return await cls._build_room_state(channel, fandom, redis)

    @classmethod
    async def toggle_raise_hand(
        cls,
        db: AsyncSession,
        channel_id: uuid.UUID,
        current_user: User,
        data: VoiceRaiseHandRequest,
        perm_checker: IPermissionChecker,
        redis: aioredis.Redis,
    ) -> VoiceRoomStateOut:
        """Allows a connected participant in a Stage Room to raise or lower their hand."""
        channel, fandom = await cls._resolve_voice_channel(db, channel_id)
        await perm_checker.verify(
            user_id=current_user.id,
            fandom_id=fandom.id,
            channel_id=channel.id,
            spec=VOICE_CONNECT_SPEC,
            error_detail="Bạn không có quyền thao tác trong phòng thoại này.",
        )

        p_key = cls._participants_key(channel.id)
        h_key = cls._raised_hands_key(channel.id)
        user_id_str = str(current_user.id)

        raw_p = await redis.hget(p_key, user_id_str)
        if not raw_p:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Bạn cần tham gia phòng thoại trước khi giơ tay phát biểu.",
            )

        p_data = json.loads(
            raw_p.decode("utf-8") if isinstance(raw_p, bytes) else str(raw_p)
        )
        p_data["is_hand_raised"] = bool(data.raised)
        await redis.hset(p_key, user_id_str, json.dumps(p_data))

        if data.raised:
            await redis.sadd(h_key, user_id_str)
            await redis.expire(h_key, cls.ROOM_TTL_SECONDS)
        else:
            await redis.srem(h_key, user_id_str)

        room_state = await cls._build_room_state(channel, fandom, redis)
        await cls._broadcast_room_state(channel.id, room_state)
        return room_state

    @classmethod
    async def manage_speaker(
        cls,
        db: AsyncSession,
        channel_id: uuid.UUID,
        target_user_id: uuid.UUID,
        current_user: User,
        data: VoiceSpeakerManageRequest,
        perm_checker: IPermissionChecker,
        redis: aioredis.Redis,
    ) -> VoiceRoomStateOut:
        """Promotes a listener to speaker, demotes to listener, or mutes/unmutes a participant (requires Mod/Owner)."""
        channel, fandom = await cls._resolve_voice_channel(db, channel_id)
        await perm_checker.verify(
            user_id=current_user.id,
            fandom_id=fandom.id,
            channel_id=channel.id,
            spec=VOICE_MODERATE_SPEC,
            error_detail="Chỉ Chủ Fandom hoặc Điều hành viên mới có quyền điều phối người phát biểu.",
        )

        p_key = cls._participants_key(channel.id)
        h_key = cls._raised_hands_key(channel.id)
        target_str = str(target_user_id)

        raw_p = await redis.hget(p_key, target_str)
        if not raw_p:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Thành viên này hiện không có mặt trong phòng thoại.",
            )

        p_data = json.loads(
            raw_p.decode("utf-8") if isinstance(raw_p, bytes) else str(raw_p)
        )
        if data.role is not None:
            p_data["role"] = data.role
            if data.role == "SPEAKER":
                p_data["is_hand_raised"] = False
                await redis.srem(h_key, target_str)
            elif data.role == "LISTENER":
                p_data["is_muted"] = True

        if data.is_muted is not None:
            p_data["is_muted"] = bool(data.is_muted)

        await redis.hset(p_key, target_str, json.dumps(p_data))
        room_state = await cls._build_room_state(channel, fandom, redis)
        await cls._broadcast_room_state(channel.id, room_state)
        return room_state

    @classmethod
    async def toggle_self_mute(
        cls,
        db: AsyncSession,
        channel_id: uuid.UUID,
        current_user: User,
        data: VoiceSelfMuteRequest,
        perm_checker: IPermissionChecker,
        redis: aioredis.Redis,
    ) -> VoiceRoomStateOut:
        """Toggles the current participant's own microphone state if they are a SPEAKER."""
        channel, fandom = await cls._resolve_voice_channel(db, channel_id)
        await perm_checker.verify(
            user_id=current_user.id,
            fandom_id=fandom.id,
            channel_id=channel.id,
            spec=VOICE_CONNECT_SPEC,
            error_detail="Bạn không có quyền kết nối phòng thoại này.",
        )

        p_key = cls._participants_key(channel.id)
        user_id_str = str(current_user.id)
        raw_p = await redis.hget(p_key, user_id_str)
        if not raw_p:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Bạn hiện chưa kết nối vào phòng thoại này.",
            )

        p_data = json.loads(
            raw_p.decode("utf-8") if isinstance(raw_p, bytes) else str(raw_p)
        )
        if not data.is_muted and p_data.get("role") != "SPEAKER":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Bạn đang ở vai trò Thính giả. Vui lòng giơ tay để được cấp quyền phát biểu.",
            )

        p_data["is_muted"] = bool(data.is_muted)
        await redis.hset(p_key, user_id_str, json.dumps(p_data))

        room_state = await cls._build_room_state(channel, fandom, redis)
        await cls._broadcast_room_state(channel.id, room_state)
        return room_state

    @classmethod
    async def mute_all_participants(
        cls,
        db: AsyncSession,
        channel_id: uuid.UUID,
        current_user: User,
        perm_checker: IPermissionChecker,
        redis: aioredis.Redis,
    ) -> VoiceRoomStateOut:
        """Mutes all non-caller participants in the voice room (requires Host/Moderator)."""
        channel, fandom = await cls._resolve_voice_channel(db, channel_id)
        await perm_checker.verify(
            user_id=current_user.id,
            fandom_id=fandom.id,
            channel_id=channel.id,
            spec=VOICE_MODERATE_SPEC,
            error_detail="Chỉ Chủ Fandom hoặc Điều hành viên mới có quyền tắt mic toàn bộ phòng thoại.",
        )

        p_key = cls._participants_key(channel.id)
        raw_map = await redis.hgetall(p_key)
        caller_id_str = str(current_user.id)

        for k, v in (raw_map or {}).items():
            uid_key = k.decode("utf-8") if isinstance(k, bytes) else str(k)
            text_val = v.decode("utf-8") if isinstance(v, bytes) else str(v)
            try:
                p_data = json.loads(text_val)
                if uid_key != caller_id_str:
                    p_data["is_muted"] = True
                    await redis.hset(p_key, uid_key, json.dumps(p_data))
            except Exception:
                continue

        room_state = await cls._build_room_state(channel, fandom, redis)
        await cls._broadcast_room_state(channel.id, room_state)
        return room_state

    @classmethod
    async def leave_voice_room(
        cls,
        db: AsyncSession,
        channel_id: uuid.UUID,
        current_user: User,
        perm_checker: IPermissionChecker,
        redis: aioredis.Redis,
    ) -> VoiceRoomStateOut:
        """Removes the current user from the voice room and frees their concurrent occupancy slot."""
        channel, fandom = await cls._resolve_voice_channel(db, channel_id)
        p_key = cls._participants_key(channel.id)
        h_key = cls._raised_hands_key(channel.id)
        active_key = cls._active_members_key(channel.id)
        user_id_str = str(current_user.id)

        await redis.hdel(p_key, user_id_str)
        await redis.srem(h_key, user_id_str)
        await redis.srem(active_key, user_id_str)

        room_state = await cls._build_room_state(channel, fandom, redis)
        await cls._broadcast_room_state(channel.id, room_state)
        return room_state
