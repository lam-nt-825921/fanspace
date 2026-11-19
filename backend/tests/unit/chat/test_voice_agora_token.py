"""Unit tests for Agora Dynamic RTC Token Builder and Voice Room permission logic (FR-11 / UC-06)."""

import uuid
import pytest

from app.modules.chat.voice_service import AgoraTokenBuilder, VoiceChannelService


def test_agora_token_builder_generates_deterministic_signed_token():
    """Verifies that AgoraTokenBuilder produces a signed Dynamic RTC Token with valid version prefix and uid."""
    app_id = "970CA35de60c44645bbae8a215061b33"
    app_cert = "5CFd2fd1755d40ecb72977518be15d3b"
    channel_name = f"voice_{uuid.uuid4().hex[:12]}"
    uid = 123456

    token_pub = AgoraTokenBuilder.build_rtc_token(
        app_id=app_id,
        app_certificate=app_cert,
        channel_name=channel_name,
        uid=uid,
        role="PUBLISHER",
        expire_seconds=3600,
    )
    token_sub = AgoraTokenBuilder.build_rtc_token(
        app_id=app_id,
        app_certificate=app_cert,
        channel_name=channel_name,
        uid=uid,
        role="SUBSCRIBER",
        expire_seconds=3600,
    )

    assert token_pub.startswith("006")
    assert token_sub.startswith("006")
    assert len(token_pub) > 40
    assert token_pub != token_sub


def test_user_uuid_to_agora_uid_is_positive_32bit_int():
    """Verifies that converting a User UUID to Agora 32-bit unsigned integer UID is deterministic and > 0."""
    user_id = uuid.uuid4()
    uid1 = VoiceChannelService.uuid_to_agora_uid(user_id)
    uid2 = VoiceChannelService.uuid_to_agora_uid(user_id)

    assert uid1 == uid2
    assert 1 <= uid1 <= 0x7FFFFFFF
