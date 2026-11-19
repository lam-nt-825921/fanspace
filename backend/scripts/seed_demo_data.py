#!/usr/bin/env python3
"""Lightweight & Full Database Seeding CLI for FanSpace Backend (Local & Heroku).

Usage inside backend directory:
  python3 -m scripts.seed_demo_data --mode fast      # Instant SQL/SVG data URLs (works without FFmpeg/Cloudinary)
  python3 -m scripts.seed_demo_data --mode full      # Full Cloudinary + FFmpeg media upload pipeline
  python3 -m scripts.seed_demo_data --clean-only     # Clean demo tables & flush Redis cache
"""

import argparse
import asyncio
import urllib.parse
import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import delete, select

import app.models  # noqa: F401
from app.core.database import AsyncSessionLocal, init_db
from app.core.redis import get_redis_client
from app.core.security import get_password_hash
from app.modules.billing.models import FandomBankAccount
from app.modules.chat.models import Channel, Message
from app.modules.chat.service import ChannelService
from app.modules.fandom.models import (
    Fandom,
    FandomEmoji,
    FandomInvite,
    FandomJoinRequest,
    FandomMember,
)
from app.modules.identity.models import User
from app.modules.rbac.models import MemberRole, MembershipPerkBit, PermissionBit, Role


def _svg_data_url(bg_hex: str, title: str, width: int = 800, height: int = 450) -> str:
    """Generates a self-contained SVG data URI banner/avatar so no external CDN or FFmpeg is required."""
    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}">'
        f'<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">'
        f'<stop offset="0%" stop-color="{bg_hex}"/>'
        f'<stop offset="100%" stop-color="#0f172a"/>'
        f"</linearGradient></defs>"
        f'<rect width="100%" height="100%" fill="url(#g)"/>'
        f'<text x="50%" y="52%" dominant-baseline="middle" text-anchor="middle" '
        f'fill="#ffffff" font-family="sans-serif" font-weight="bold" font-size="{max(22, height // 12)}">'
        f"{title}</text></svg>"
    )
    return f"data:image/svg+xml;utf8,{urllib.parse.quote(svg)}"


DEMO_COMMUNITIES = [
    {
        "owner": {
            "username": "sontung_sky",
            "email": "sontung.sky@fanspace.vn",
            "display_name": "Nguyễn Thanh Tùng",
        },
        "fandom": {
            "name": "Hội Sky - Sơn Tùng M-TP Official",
            "slug": "sky-son-tung-mtp",
            "category": "Âm nhạc",
            "admission_mode": "OPEN",
            "is_public": True,
            "member_count": 5240,
            "color": "#1E3A8A",
            "description": (
                "Cộng đồng người hâm mộ chính thức của nghệ sĩ Sơn Tùng M-TP. Nơi hội tụ những trái tim nhiệt huyết "
                "của gia đình Sky trên toàn quốc và quốc tế, cập nhật lịch trình concert, thảo luận âm nhạc và giao lưu trực tiếp."
            ),
            "rules_tos": (
                "1. Tôn trọng nghệ sĩ và các thành viên khác trong cộng đồng.\n"
                "2. Không phát ngôn tiêu cực hoặc gây chia rẽ.\n"
                "3. Tuân thủ bản quyền âm nhạc và hình ảnh chính thức."
            ),
        },
    },
    {
        "owner": {
            "username": "t1_faker_vn",
            "email": "t1.faker@fanspace.vn",
            "display_name": "Trần Minh Đức",
        },
        "fandom": {
            "name": "T1 & Faker Fanclub Việt Nam",
            "slug": "t1-faker-vietnam",
            "category": "Game & Esports",
            "admission_mode": "OPEN",
            "is_public": True,
            "member_count": 8920,
            "color": "#991B1B",
            "description": (
                "Ngôi nhà chung của người hâm mộ đội tuyển Liên Minh Huyền Thoại T1 và Quỷ Vương Bất Tử Lee 'Faker' Sang-hyeok "
                "tại Việt Nam. Cùng nhau cổ vũ T1 tại LCK, MSI, CKTG và tổ chức viewing party."
            ),
            "rules_tos": (
                "1. Cổ vũ văn minh, không toxic hay xúc phạm các đội tuyển đối thủ.\n"
                "2. Nghiêm cấm mua bán tài khoản hoặc phát tán phần mềm gian lận."
            ),
        },
    },
    {
        "owner": {
            "username": "monkey_d_luffy",
            "email": "luffy.strawhat@fanspace.vn",
            "display_name": "Hoàng Nam Phong",
        },
        "fandom": {
            "name": "Cộng Đồng Băng Mũ Rơm - One Piece VN",
            "slug": "one-piece-bang-mu-rom",
            "category": "Phim ảnh & Anime",
            "admission_mode": "APPROVAL",
            "is_public": True,
            "member_count": 3410,
            "color": "#D97706",
            "description": (
                "Cộng đồng dành riêng cho các tín đồ của tác phẩm manga/anime huyền thoại One Piece. "
                "Nơi trao đổi giả thuyết cốt truyện, phân tích chap mới nhất và chia sẻ fanart."
            ),
            "rules_tos": (
                "1. Bắt buộc gắn thẻ Cảnh báo Spoil khi thảo luận chap manga mới.\n"
                "2. Tôn trọng bản quyền tác giả và nguồn gốc các ấn phẩm sưu tầm."
            ),
        },
    },
    {
        "owner": {
            "username": "madridista_vietnam",
            "email": "madridista@fanspace.vn",
            "display_name": "Phạm Hoàng Long",
        },
        "fandom": {
            "name": "Madridistas Việt Nam - Real Madrid FC",
            "slug": "madridistas-vietnam",
            "category": "Thể thao",
            "admission_mode": "OPEN",
            "is_public": True,
            "member_count": 6150,
            "color": "#4338CA",
            "description": (
                "Hội cổ động viên Real Madrid Club de Fútbol chính thức tại Việt Nam. Nơi tụ họp của các Madridistas "
                "chia sẻ niềm tự hào về 15 danh hiệu UEFA Champions League và lịch thi đấu hàng tuần."
            ),
            "rules_tos": (
                "1. Giữ gìn hình ảnh văn minh của cộng đồng Madridistas Việt Nam.\n"
                "2. Nghiêm cấm bàn luận cá độ hoặc phát ngôn thù địch."
            ),
        },
    },
    {
        "owner": {
            "username": "nguyentronglam",
            "email": "lam.ai.engineer@fanspace.vn",
            "display_name": "Nguyễn Trọng Lâm",
        },
        "fandom": {
            "name": "Cộng Đồng Kỹ Sư Trí Tuệ Nhân Tạo (AI Hub)",
            "slug": "ai-engineers-hub",
            "category": "Công nghệ",
            "admission_mode": "OPEN",
            "is_public": True,
            "member_count": 1890,
            "color": "#0F766E",
            "description": (
                "Không gian kết nối các chuyên gia, nhà nghiên cứu và kỹ sư Trí tuệ Nhân tạo (AI), Machine Learning và LLM "
                "tại Việt Nam. Thảo luận Agentic Workflows, PyTorch, System Architecture và cơ hội nghề nghiệp."
            ),
            "rules_tos": (
                "1. Thảo luận chuyên môn văn minh, không spam tin tuyển dụng sai kênh.\n"
                "2. Khuyến khích chia sẻ mã nguồn mở và kinh nghiệm thực chiến."
            ),
        },
    },
]


async def seed_fast(clean_first: bool = True, clean_only: bool = False) -> None:
    """Seeds comprehensive demo data (Users, Fandoms, Channels, Roles, VIP Tiers, Bank Account, Messages) without external dependencies."""
    await init_db()
    redis = get_redis_client()
    try:
        await redis.flushdb()
        print("✅ [Redis] Đã xóa sạch bộ nhớ đệm Redis.")
    except Exception as e:
        print(f"⚠️ [Redis] Bỏ qua flushdb: {e}")

    async with AsyncSessionLocal() as db:
        if clean_first or clean_only:
            print("🧹 [Database] Đang dọn dẹp dữ liệu cũ...")
            await db.execute(delete(Message))
            await db.execute(delete(Channel))
            await db.execute(delete(MemberRole))
            await db.execute(delete(Role))
            await db.execute(delete(FandomEmoji))
            await db.execute(delete(FandomBankAccount))
            await db.execute(delete(FandomMember))
            await db.execute(delete(FandomInvite))
            await db.execute(delete(FandomJoinRequest))
            await db.execute(delete(Fandom))
            await db.execute(delete(User))
            await db.commit()
            print("✅ [Database] Đã làm sạch các bảng dữ liệu.")
            if clean_only:
                return

        pwd_hash = get_password_hash("Fanspace@2026")
        users_by_username: dict[str, User] = {}

        # Create demo fan user for immediate login testing
        demo_fan = User(
            username="fan_demo",
            email="demo@fanspace.vn",
            display_name="Thành Viên Demo",
            password_hash=pwd_hash,
            bio="Tài khoản trải nghiệm hệ thống FanSpace (Mật khẩu: Fanspace@2026)",
            is_active=True,
            is_email_verified=True,
        )
        db.add(demo_fan)
        await db.flush()
        users_by_username["fan_demo"] = demo_fan

        for item in DEMO_COMMUNITIES:
            o_data = item["owner"]
            f_data = item["fandom"]
            uname = o_data["username"]

            if uname not in users_by_username:
                owner = User(
                    username=uname,
                    email=o_data["email"],
                    display_name=o_data["display_name"],
                    password_hash=pwd_hash,
                    is_active=True,
                    is_email_verified=True,
                )
                db.add(owner)
                await db.flush()
                users_by_username[uname] = owner
            else:
                owner = users_by_username[uname]

            slug = f_data["slug"]
            color = f_data["color"]
            fandom = Fandom(
                name=f_data["name"],
                slug=slug,
                description=f_data["description"],
                category=f_data["category"],
                avatar_url=_svg_data_url(color, f_data["name"][:12], 400, 400),
                banner_url=_svg_data_url(color, f_data["name"], 1280, 420),
                illustration_urls=[
                    _svg_data_url(color, f"{f_data['name']} #1", 800, 500),
                    _svg_data_url("#312E81", f"{f_data['name']} #2", 800, 500),
                ],
                admission_mode=f_data["admission_mode"],
                is_public=f_data["is_public"],
                rules_tos=f_data["rules_tos"],
                member_count=f_data["member_count"],
                owner_id=owner.id,
            )
            db.add(fandom)
            await db.flush()

            # Owner & demo_fan membership
            db.add(FandomMember(fandom_id=fandom.id, user_id=owner.id, status="ACTIVE"))
            db.add(FandomMember(fandom_id=fandom.id, user_id=demo_fan.id, status="ACTIVE"))

            # Bank Account for SePay VietQR checkout (FR-09)
            db.add(
                FandomBankAccount(
                    fandom_id=fandom.id,
                    bank_code="MBBank",
                    account_number="0988777666",
                    account_name="NGUYEN TRONG LAM",
                    is_active=True,
                )
            )

            # Custom Role (FR-08) & VIP Membership Tiers (FR-09)
            mod_role = Role(
                fandom_id=fandom.id,
                name="Điều Phối Viên",
                color_hex="#3B82F6",
                priority=60,
                permissions_bitmask=(
                    PermissionBit.READ_MESSAGES
                    | PermissionBit.SEND_MESSAGES
                    | PermissionBit.ATTACH_FILES
                    | PermissionBit.EMBED_LINKS
                    | PermissionBit.MODERATE_CHAT
                    | PermissionBit.VOICE_CONNECT
                    | PermissionBit.VOICE_SPEAK
                    | PermissionBit.BYPASS_SLOWMODE
                ),
                is_membership_tier=False,
            )
            tier1_role = Role(
                fandom_id=fandom.id,
                name="Hội Viên Bạc (Silver VIP)",
                color_hex="#10B981",
                priority=30,
                permissions_bitmask=0,
                membership_perks_bitmask=MembershipPerkBit.DEFAULT_TIER_PERKS,
                is_membership_tier=True,
                tier_level=1,
                price_fiat_vnd=29000,
                duration_days=30,
            )
            tier2_role = Role(
                fandom_id=fandom.id,
                name="Hội Viên Vàng (Gold VIP)",
                color_hex="#F59E0B",
                priority=40,
                permissions_bitmask=0,
                membership_perks_bitmask=MembershipPerkBit.DEFAULT_TIER_PERKS,
                is_membership_tier=True,
                tier_level=2,
                price_fiat_vnd=79000,
                duration_days=30,
            )
            db.add_all([mod_role, tier1_role, tier2_role])
            await db.flush()

            # Channels (Default + VIP Channel + Stage Voice Room) (FR-10 & FR-11)
            default_channels = ChannelService.build_default_channels(fandom.id)
            vip_channel = Channel(
                fandom_id=fandom.id,
                name="khu-vuc-vip",
                type="TEXT",
                topic="Phòng thảo luận đặc quyền dành riêng cho Hội viên VIP (Miễn Slow-mode)",
                position=3,
                is_announcement=False,
                is_membership_only=True,
                min_membership_tier_level=1,
                membership_bypass_slowmode=True,
                slow_mode_seconds=15,
                max_members=100,
            )
            stage_voice = Channel(
                fandom_id=fandom.id,
                name="Sân Khấu Giao Lưu (Stage)",
                type="VOICE",
                topic="Sân khấu âm thanh trực tiếp qua Agora RTC — Thính giả giơ tay để phát biểu",
                position=4,
                is_announcement=False,
                is_membership_only=False,
                voice_room_type="STAGE_ROOM",
                max_members=50,
            )
            all_channels = [*default_channels, vip_channel, stage_voice]
            db.add_all(all_channels)
            await db.flush()

            # Sample welcome messages
            ann_ch = default_channels[0]
            gen_ch = default_channels[1]
            db.add_all(
                [
                    Message(
                        channel_id=ann_ch.id,
                        sender_id=owner.id,
                        content=f"🎉 Chào mừng các thành viên đến với không gian chính thức của {f_data['name']}!",
                        is_pinned=True,
                        reactions={"🔥": [str(owner.id), str(demo_fan.id)]},
                    ),
                    Message(
                        channel_id=gen_ch.id,
                        sender_id=owner.id,
                        content="Hãy giới thiệu bản thân và giao lưu cùng mọi người tại đây nhé!",
                        is_pinned=False,
                        reactions={"❤️": [str(demo_fan.id)]},
                    ),
                    Message(
                        channel_id=gen_ch.id,
                        sender_id=demo_fan.id,
                        content="Chào cả nhà! Rất vui được tham gia cộng đồng trên FanSpace!",
                        is_pinned=False,
                        reactions={},
                    ),
                ]
            )

        await db.commit()

    print("\n==================================================================")
    print("🎉 HOÀN TẤT SEED DỮ LIỆU DEMO FANSPACE (CHẾ ĐỘ FAST)!")
    print("==================================================================")
    print("🔑 Tài khoản đăng nhập thử nghiệm (Mật khẩu chung: Fanspace@2026):")
    print("   • Tài khoản Fan Demo : demo@fanspace.vn (username: fan_demo)")
    for item in DEMO_COMMUNITIES:
        o = item["owner"]
        f = item["fandom"]
        print(f"   • Chủ Fandom [{f['slug']}]: {o['email']} (@{o['username']})")
    print("==================================================================\n")


async def main() -> None:
    parser = argparse.ArgumentParser(description="FanSpace Backend Data Seeder")
    parser.add_argument(
        "--mode",
        choices=["fast", "full"],
        default="fast",
        help="Chế độ seed: 'fast' (tức thì, không cần FFmpeg/Cloudinary) hoặc 'full' (sinh ảnh/video FFmpeg & tải lên Cloudinary)",
    )
    parser.add_argument(
        "--clean-only",
        action="store_true",
        help="Chỉ xóa sạch dữ liệu cũ và flush Redis mà không thêm dữ liệu mới",
    )
    parser.add_argument(
        "--no-clean",
        action="store_true",
        help="Không xóa dữ liệu hiện có trước khi seed",
    )
    args = parser.parse_args()

    if args.clean_only:
        await seed_fast(clean_first=True, clean_only=True)
        return

    if args.mode == "full":
        from scripts.seed_fr02_fandoms import main as run_full_seed

        await run_full_seed()
    else:
        await seed_fast(clean_first=not args.no_clean, clean_only=False)


if __name__ == "__main__":
    asyncio.run(main())
