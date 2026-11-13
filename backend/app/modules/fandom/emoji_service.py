"""Domain logic, schemas, and service for Fandom-exclusive Emojis and Stickers."""

from __future__ import annotations

import re
import uuid
from collections.abc import Iterable
from datetime import datetime, timezone
from typing import Literal

from fastapi import HTTPException, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.fandom.models import Fandom, FandomEmoji
from app.modules.fandom.service import FandomService
from app.modules.identity.models import User
from app.modules.rbac.models import MemberRole, MembershipPerkBit, PermissionBit, Role

EmojiAssetType = Literal["EMOJI", "STICKER"]

_EMOJI_CODE_REGEX = re.compile(r"^[a-z0-9][a-z0-9_-]{1,62}[a-z0-9]$")
_SHORTCODE_EXTRACT_REGEX = re.compile(r":([a-zA-Z0-9][a-zA-Z0-9_-]{1,62}[a-zA-Z0-9]):")


def normalize_emoji_code(raw_code: str) -> str:
    """Normalizes and validates a Fandom emoji/sticker shortcode (strips colons and lowercases)."""
    cleaned = raw_code.strip().strip(":").strip().lower()
    if not _EMOJI_CODE_REGEX.match(cleaned):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                "Mã shortcode chỉ được chứa chữ cái thường, chữ số, dấu gạch dưới (_) "
                "hoặc gạch ngang (-), độ dài từ 3 đến 64 ký tự."
            ),
        )
    return cleaned


def extract_emoji_shortcodes(text: str | None) -> set[str]:
    """Extracts all unique lowercase `:shortcode:` tokens from a chat message string."""
    if not text:
        return set()
    return {m.group(1).lower() for m in _SHORTCODE_EXTRACT_REGEX.finditer(text)}


def is_fandom_emoji_unlocked(
    is_owner: bool,
    user_tier_level: int,
    user_perks_bitmask: int,
    emoji_min_tier_level: int,
    asset_type: str = "EMOJI",
) -> bool:
    """Determines whether a user can use a specific Fandom Emoji or Sticker."""
    if is_owner:
        return True
    if user_tier_level < int(emoji_min_tier_level or 1):
        return False
    required_perk = (
        MembershipPerkBit.EXCLUSIVE_STICKERS
        if (asset_type or "EMOJI").upper() == "STICKER"
        else MembershipPerkBit.EXCLUSIVE_EMOJIS
    )
    return bool(user_perks_bitmask & required_perk)


class FandomEmojiCreate(BaseModel):
    """Payload for creating a custom Fandom Emoji or Sticker (Owner/Admin)."""

    code: str = Field(..., min_length=3, max_length=66, description="Shortcode (ví dụ: star_glow)")
    name: str = Field(..., min_length=1, max_length=100, description="Tên hiển thị của Emoji/Sticker")
    asset_type: EmojiAssetType = Field(default="EMOJI", description="Loại tài nguyên: EMOJI hoặc STICKER")
    image_url: str = Field(..., min_length=5, max_length=2048, description="Đường dẫn ảnh Emoji/Sticker")
    min_tier_level: int = Field(
        default=1,
        ge=1,
        le=4,
        description="Cấp độ gói Hội viên tối thiểu (1..4) để mở khóa",
    )


class FandomEmojiUpdate(BaseModel):
    """Payload for updating an existing Fandom Emoji or Sticker."""

    code: str | None = Field(default=None, min_length=3, max_length=66)
    name: str | None = Field(default=None, min_length=1, max_length=100)
    asset_type: EmojiAssetType | None = None
    image_url: str | None = Field(default=None, min_length=5, max_length=2048)
    min_tier_level: int | None = Field(default=None, ge=1, le=4)


class FandomEmojiOut(BaseModel):
    """Serialized Fandom Emoji/Sticker with caller's unlock status."""

    id: uuid.UUID
    fandom_id: uuid.UUID
    code: str
    shortcode: str
    name: str
    asset_type: EmojiAssetType
    image_url: str
    min_tier_level: int
    min_tier_name: str
    is_unlocked: bool = False
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class FandomEmojiListOut(BaseModel):
    """Response payload listing all custom Emojis and Stickers in a Fandom."""

    fandom_id: uuid.UUID
    user_highest_tier_level: int = 0
    user_perks_bitmask: int = 0
    items: list[FandomEmojiOut] = Field(default_factory=list)


class FandomEmojiService:
    """Service managing Fandom-exclusive Emojis/Stickers and chat usage enforcement."""

    @staticmethod
    async def get_user_active_tier_and_perks(
        db: AsyncSession,
        fandom: Fandom,
        user_id: uuid.UUID | None,
    ) -> tuple[int, int]:
        """Returns `(highest_active_tier_level, combined_perks_bitmask)` for `user_id` in `fandom`."""
        if user_id is None:
            return 0, 0
        if fandom.owner_id == user_id:
            return 4, int(MembershipPerkBit.DEFAULT_TIER_PERKS)

        now = datetime.now(timezone.utc)
        res = await db.execute(
            select(MemberRole, Role)
            .join(Role, Role.id == MemberRole.role_id)
            .where(
                MemberRole.fandom_id == fandom.id,
                MemberRole.user_id == user_id,
                Role.is_membership_tier.is_(True),
            )
        )
        max_tier = 0
        perks_mask = 0
        for mr, role in res.all():
            if mr.expires_at is None or mr.expires_at > now:
                level = int(role.tier_level or 1)
                if level > max_tier:
                    max_tier = level
                perks_mask |= int(
                    role.membership_perks_bitmask
                    if role.membership_perks_bitmask is not None
                    else MembershipPerkBit.DEFAULT_TIER_PERKS
                )
        return max_tier, perks_mask

    @staticmethod
    async def _load_tier_names_by_level(
        db: AsyncSession, fandom_id: uuid.UUID
    ) -> dict[int, str]:
        """Maps `tier_level -> role.name` for all Membership Tiers in a Fandom."""
        res = await db.execute(
            select(Role).where(
                Role.fandom_id == fandom_id,
                Role.is_membership_tier.is_(True),
            )
        )
        mapping: dict[int, str] = {}
        for r in res.scalars().all():
            lvl = int(r.tier_level or 1)
            mapping.setdefault(lvl, r.name)
        return mapping

    @classmethod
    def _serialize_emoji(
        cls,
        item: FandomEmoji,
        tier_names: dict[int, str],
        is_owner: bool,
        user_tier_level: int,
        user_perks_bitmask: int,
    ) -> FandomEmojiOut:
        lvl = int(item.min_tier_level or 1)
        asset_type: EmojiAssetType = (
            "STICKER" if (item.asset_type or "").upper() == "STICKER" else "EMOJI"
        )
        unlocked = is_fandom_emoji_unlocked(
            is_owner=is_owner,
            user_tier_level=user_tier_level,
            user_perks_bitmask=user_perks_bitmask,
            emoji_min_tier_level=lvl,
            asset_type=asset_type,
        )
        return FandomEmojiOut(
            id=item.id,
            fandom_id=item.fandom_id,
            code=item.code,
            shortcode=f":{item.code}:",
            name=item.name,
            asset_type=asset_type,
            image_url=item.image_url,
            min_tier_level=lvl,
            min_tier_name=tier_names.get(lvl, f"Hội viên Cấp {lvl}"),
            is_unlocked=unlocked,
            created_at=item.created_at,
        )

    @classmethod
    async def list_fandom_emojis(
        cls,
        db: AsyncSession,
        identifier: str,
        current_user: User | None = None,
    ) -> FandomEmojiListOut:
        """Lists all custom Emojis and Stickers for a Fandom along with caller's unlock status."""
        fandom = await FandomService._resolve_fandom(db, identifier)
        user_id = current_user.id if current_user else None
        is_owner = user_id is not None and fandom.owner_id == user_id
        user_tier_level, user_perks_bitmask = await cls.get_user_active_tier_and_perks(
            db, fandom, user_id
        )
        tier_names = await cls._load_tier_names_by_level(db, fandom.id)

        res = await db.execute(
            select(FandomEmoji)
            .where(FandomEmoji.fandom_id == fandom.id)
            .order_by(
                FandomEmoji.asset_type.asc(),
                FandomEmoji.min_tier_level.asc(),
                FandomEmoji.created_at.asc(),
            )
        )
        rows = list(res.scalars().all())
        return FandomEmojiListOut(
            fandom_id=fandom.id,
            user_highest_tier_level=user_tier_level,
            user_perks_bitmask=user_perks_bitmask,
            items=[
                cls._serialize_emoji(
                    row, tier_names, is_owner, user_tier_level, user_perks_bitmask
                )
                for row in rows
            ],
        )

    @staticmethod
    async def _require_owner_or_admin(
        db: AsyncSession, fandom: Fandom, current_user: User
    ) -> None:
        """Verifies that `current_user` is the Fandom Owner or holds ADMINISTRATOR permission."""
        if fandom.owner_id == current_user.id:
            return
        res = await db.execute(
            select(Role)
            .join(MemberRole, MemberRole.role_id == Role.id)
            .where(
                MemberRole.fandom_id == fandom.id,
                MemberRole.user_id == current_user.id,
            )
        )
        for role in res.scalars().all():
            if int(role.permissions_bitmask or 0) & PermissionBit.ADMINISTRATOR:
                return
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Chỉ Chủ sở hữu hoặc Quản trị viên Fandom mới có quyền thiết lập Emoji & Sticker độc quyền.",
        )

    @classmethod
    async def create_fandom_emoji(
        cls,
        db: AsyncSession,
        identifier: str,
        current_user: User,
        data: FandomEmojiCreate,
    ) -> FandomEmojiOut:
        """Creates a new Fandom Emoji or Sticker and sets its required membership tier level (1..4)."""
        fandom = await FandomService._resolve_fandom(db, identifier)
        await cls._require_owner_or_admin(db, fandom, current_user)

        normalized_code = normalize_emoji_code(data.code)
        dup_res = await db.execute(
            select(FandomEmoji).where(
                FandomEmoji.fandom_id == fandom.id,
                func.lower(FandomEmoji.code) == normalized_code,
            )
        )
        if dup_res.scalar_one_or_none() is not None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"Mã shortcode ':{normalized_code}:' đã tồn tại trong Fandom này.",
            )

        asset_type: EmojiAssetType = (
            "STICKER" if (data.asset_type or "").upper() == "STICKER" else "EMOJI"
        )
        new_emoji = FandomEmoji(
            fandom_id=fandom.id,
            code=normalized_code,
            name=data.name.strip(),
            asset_type=asset_type,
            image_url=data.image_url.strip(),
            min_tier_level=int(data.min_tier_level or 1),
            created_by=current_user.id,
        )
        db.add(new_emoji)
        await db.commit()
        await db.refresh(new_emoji)

        tier_names = await cls._load_tier_names_by_level(db, fandom.id)
        return cls._serialize_emoji(
            new_emoji,
            tier_names=tier_names,
            is_owner=True,
            user_tier_level=4,
            user_perks_bitmask=int(MembershipPerkBit.DEFAULT_TIER_PERKS),
        )

    @classmethod
    async def update_fandom_emoji(
        cls,
        db: AsyncSession,
        identifier: str,
        emoji_id: uuid.UUID,
        current_user: User,
        data: FandomEmojiUpdate,
    ) -> FandomEmojiOut:
        """Updates an existing Fandom Emoji or Sticker (shortcode, name, asset_type, or min_tier_level)."""
        fandom = await FandomService._resolve_fandom(db, identifier)
        await cls._require_owner_or_admin(db, fandom, current_user)

        res = await db.execute(
            select(FandomEmoji).where(
                FandomEmoji.id == emoji_id,
                FandomEmoji.fandom_id == fandom.id,
            )
        )
        emoji = res.scalar_one_or_none()
        if emoji is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Không tìm thấy Emoji/Sticker trong Fandom này.",
            )

        if data.code is not None:
            normalized_code = normalize_emoji_code(data.code)
            if normalized_code != emoji.code.lower():
                dup_res = await db.execute(
                    select(FandomEmoji).where(
                        FandomEmoji.fandom_id == fandom.id,
                        func.lower(FandomEmoji.code) == normalized_code,
                        FandomEmoji.id != emoji.id,
                    )
                )
                if dup_res.scalar_one_or_none() is not None:
                    raise HTTPException(
                        status_code=status.HTTP_409_CONFLICT,
                        detail=f"Mã shortcode ':{normalized_code}:' đã tồn tại trong Fandom này.",
                    )
                emoji.code = normalized_code

        if data.name is not None:
            emoji.name = data.name.strip()
        if data.asset_type is not None:
            emoji.asset_type = (
                "STICKER" if data.asset_type.upper() == "STICKER" else "EMOJI"
            )
        if data.image_url is not None:
            emoji.image_url = data.image_url.strip()
        if data.min_tier_level is not None:
            emoji.min_tier_level = int(data.min_tier_level)

        await db.commit()
        await db.refresh(emoji)

        tier_names = await cls._load_tier_names_by_level(db, fandom.id)
        return cls._serialize_emoji(
            emoji,
            tier_names=tier_names,
            is_owner=True,
            user_tier_level=4,
            user_perks_bitmask=int(MembershipPerkBit.DEFAULT_TIER_PERKS),
        )

    @classmethod
    async def delete_fandom_emoji(
        cls,
        db: AsyncSession,
        identifier: str,
        emoji_id: uuid.UUID,
        current_user: User,
    ) -> dict[str, str]:
        """Deletes a Fandom Emoji or Sticker."""
        fandom = await FandomService._resolve_fandom(db, identifier)
        await cls._require_owner_or_admin(db, fandom, current_user)

        res = await db.execute(
            select(FandomEmoji).where(
                FandomEmoji.id == emoji_id,
                FandomEmoji.fandom_id == fandom.id,
            )
        )
        emoji = res.scalar_one_or_none()
        if emoji is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Không tìm thấy Emoji/Sticker trong Fandom này.",
            )

        code = emoji.code
        await db.delete(emoji)
        await db.commit()
        return {"message": f"Đã xóa Emoji/Sticker ':{code}:' thành công."}

    @classmethod
    async def validate_message_emojis_and_stickers(
        cls,
        db: AsyncSession,
        fandom: Fandom,
        current_user: User,
        content: str | None,
        attachments: Iterable[object] | None = None,
    ) -> None:
        """Enforces that any Fandom `:shortcode:` or Sticker attachment used is unlocked by `current_user`."""
        if fandom.owner_id == current_user.id:
            return

        shortcodes = extract_emoji_shortcodes(content)
        sticker_urls: set[str] = set()
        for att in attachments or []:
            att_type = (getattr(att, "type", None) or "").upper()
            att_url = getattr(att, "url", None) or ""
            att_filename = getattr(att, "filename", None) or ""
            if att_type == "STICKER":
                if att_url:
                    sticker_urls.add(att_url.strip())
                shortcodes |= extract_emoji_shortcodes(att_filename)

        if not shortcodes and not sticker_urls:
            return

        res = await db.execute(
            select(FandomEmoji).where(FandomEmoji.fandom_id == fandom.id)
        )
        all_fandom_emojis = list(res.scalars().all())
        if not all_fandom_emojis:
            return

        matched: list[FandomEmoji] = [
            e
            for e in all_fandom_emojis
            if e.code.lower() in shortcodes or e.image_url in sticker_urls
        ]
        if not matched:
            return

        user_tier_level, user_perks_bitmask = await cls.get_user_active_tier_and_perks(
            db, fandom, current_user.id
        )
        tier_names = await cls._load_tier_names_by_level(db, fandom.id)

        for emoji in matched:
            if not is_fandom_emoji_unlocked(
                is_owner=False,
                user_tier_level=user_tier_level,
                user_perks_bitmask=user_perks_bitmask,
                emoji_min_tier_level=emoji.min_tier_level,
                asset_type=emoji.asset_type,
            ):
                tier_label = tier_names.get(
                    emoji.min_tier_level, f"Hội viên Cấp {emoji.min_tier_level}"
                )
                kind_label = (
                    "Sticker"
                    if (emoji.asset_type or "").upper() == "STICKER"
                    else "Emoji"
                )
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=(
                        f"{kind_label} độc quyền ':{emoji.code}:' ({emoji.name}) "
                        f"yêu cầu gói '{tier_label}' (Cấp {emoji.min_tier_level}) trở lên để mở khóa."
                    ),
                )

    @classmethod
    async def validate_reaction_emoji(
        cls,
        db: AsyncSession,
        fandom: Fandom,
        current_user: User,
        emoji_str: str,
    ) -> None:
        """Verifies that a custom `:shortcode:` reaction is unlocked by `current_user`."""
        if fandom.owner_id == current_user.id:
            return
        cleaned = emoji_str.strip()
        if not (cleaned.startswith(":") and cleaned.endswith(":") and len(cleaned) >= 4):
            return
        code = cleaned.strip(":").lower()
        res = await db.execute(
            select(FandomEmoji).where(
                FandomEmoji.fandom_id == fandom.id,
                func.lower(FandomEmoji.code) == code,
            )
        )
        custom_emoji = res.scalar_one_or_none()
        if custom_emoji is None:
            return

        user_tier_level, user_perks_bitmask = await cls.get_user_active_tier_and_perks(
            db, fandom, current_user.id
        )
        if not is_fandom_emoji_unlocked(
            is_owner=False,
            user_tier_level=user_tier_level,
            user_perks_bitmask=user_perks_bitmask,
            emoji_min_tier_level=custom_emoji.min_tier_level,
            asset_type=custom_emoji.asset_type,
        ):
            tier_names = await cls._load_tier_names_by_level(db, fandom.id)
            tier_label = tier_names.get(
                custom_emoji.min_tier_level,
                f"Hội viên Cấp {custom_emoji.min_tier_level}",
            )
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=(
                    f"Biểu cảm độc quyền ':{custom_emoji.code}:' yêu cầu gói '{tier_label}' "
                    f"(Cấp {custom_emoji.min_tier_level}) trở lên để thả biểu cảm."
                ),
            )
