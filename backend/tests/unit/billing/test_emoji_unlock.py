"""Unit tests for Fandom exclusive Emoji & Sticker shortcode extraction and unlock evaluation."""

import pytest
from fastapi import HTTPException

from app.modules.rbac.models import MembershipPerkBit
from app.modules.fandom.emoji_service import (
    extract_emoji_shortcodes,
    is_fandom_emoji_unlocked,
    normalize_emoji_code,
)


def test_normalize_emoji_code_and_extract_shortcodes():
    """Verifies shortcode normalization and extraction from chat message content."""
    assert normalize_emoji_code(":Star_Glow:") == "star_glow"
    assert normalize_emoji_code("  fire-heart_01 ") == "fire-heart_01"

    with pytest.raises(HTTPException) as exc_info:
        normalize_emoji_code("a!")
    assert exc_info.value.status_code == 400

    codes = extract_emoji_shortcodes(
        "Chào Fandom :star_glow: cùng thả :fire-heart_01: và :star_glow: nhé!"
    )
    assert codes == {"star_glow", "fire-heart_01"}


def test_is_fandom_emoji_unlocked_by_tier_and_perk_bitmask():
    """Verifies unlock rules for Owner, Tier level, and MembershipPerkBit."""
    both_perks = int(
        MembershipPerkBit.EXCLUSIVE_EMOJIS | MembershipPerkBit.EXCLUSIVE_STICKERS
    )
    only_emoji_perk = int(MembershipPerkBit.EXCLUSIVE_EMOJIS)

    # 1. Owner always unlocks everything regardless of tier
    assert (
        is_fandom_emoji_unlocked(
            is_owner=True,
            user_tier_level=0,
            user_perks_bitmask=0,
            emoji_min_tier_level=4,
            asset_type="STICKER",
        )
        is True
    )

    # 2. Free member (tier 0) cannot unlock Tier 1 emoji
    assert (
        is_fandom_emoji_unlocked(
            is_owner=False,
            user_tier_level=0,
            user_perks_bitmask=both_perks,
            emoji_min_tier_level=1,
            asset_type="EMOJI",
        )
        is False
    )

    # 3. Tier 1 member unlocks Tier 1 emoji, but NOT Tier 2 emoji
    assert (
        is_fandom_emoji_unlocked(
            is_owner=False,
            user_tier_level=1,
            user_perks_bitmask=both_perks,
            emoji_min_tier_level=1,
            asset_type="EMOJI",
        )
        is True
    )
    assert (
        is_fandom_emoji_unlocked(
            is_owner=False,
            user_tier_level=1,
            user_perks_bitmask=both_perks,
            emoji_min_tier_level=2,
            asset_type="EMOJI",
        )
        is False
    )

    # 4. Tier 3 member with only EXCLUSIVE_EMOJIS perk cannot unlock a STICKER
    assert (
        is_fandom_emoji_unlocked(
            is_owner=False,
            user_tier_level=3,
            user_perks_bitmask=only_emoji_perk,
            emoji_min_tier_level=1,
            asset_type="STICKER",
        )
        is False
    )
