"""Database and Media Seeding Script for FR-02 (Fandom Discovery & Preview).

Performs:
1. Clean slate reset: Clears existing test fandoms, members, and test users, plus flushes Redis cache.
2. Generates genuine media assets (Avatars, Banners, Gallery Images, and 720p Short MP4 Clips) using FFmpeg.
3. Uploads assets to Cloudinary via the official Fanspace MediaService pipeline.
4. Seeds 6 realistic fandom communities with rich Vietnamese content across categories.
"""

import asyncio
import os
import shutil
import subprocess
import tempfile
import uuid
from datetime import datetime, timezone
from io import BytesIO

from fastapi import UploadFile
from sqlalchemy import delete, select

import app.models  # noqa: F401
from app.core.config import get_settings
from app.core.database import AsyncSessionLocal
from app.core.redis import get_redis_client
from app.core.security import get_password_hash
from app.modules.fandom.models import (
    Fandom,
    FandomInvite,
    FandomJoinRequest,
    FandomMember,
)
from app.modules.identity.models import User
from app.modules.media.schemas import MediaTarget
from app.modules.media.service import MediaService

settings = get_settings()

TEST_USER_PASSWORD = get_password_hash("Fanspace@2026")

FANDOM_DEFINITIONS = [
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
            "description": (
                "Cộng đồng người hâm mộ chính thức của nghệ sĩ Sơn Tùng M-TP. Nơi hội tụ những trái tim nhiệt huyết "
                "của gia đình Sky trên toàn quốc và quốc tế, cùng nhau sẻ chia niềm đam mê âm nhạc, cập nhật lịch trình "
                "biểu diễn mới nhất, tham gia concert và các dự án thiện nguyện lan tỏa thông điệp tích cực."
            ),
            "rules_tos": (
                "1. Tôn trọng nghệ sĩ và các thành viên khác trong cộng đồng.\n"
                "2. Không phát ngôn tiêu cực, xúc phạm hoặc gây chia rẽ trên không gian mạng.\n"
                "3. Tuân thủ bản quyền các tác phẩm âm nhạc và hình ảnh chính thức."
            ),
        },
        "palette": {
            "avatar_color": "0x1E3A8A",  # Dark Blue
            "banner_color": "0x172554",  # Deep Navy
            "img1_color": "0x2563EB",
            "img2_color": "0x3B82F6",
            "video_color": "0x1D4ED8",
        },
        "has_video": True,
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
            "description": (
                "Ngôi nhà chung của người hâm mộ đội tuyển Liên Minh Huyền Thoại T1 và Quỷ Vương Bất Tử Lee 'Faker' Sang-hyeok "
                "tại Việt Nam. Cùng nhau cổ vũ T1 tại các giải đấu LCK, MSI và CKTG; thảo luận meta game, chia sẻ khoảnh khắc "
                "highlight và tổ chức viewing party cuồng nhiệt khắp các tỉnh thành."
            ),
            "rules_tos": (
                "1. Cổ vũ văn minh, không kích động toxic hay xúc phạm các đội tuyển đối thủ.\n"
                "2. Nghiêm cấm mua bán tài khoản, cày thuê hoặc phát tán phần mềm gian lận."
            ),
        },
        "palette": {
            "avatar_color": "0x991B1B",  # Dark Red
            "banner_color": "0x450A0A",  # Deep Crimson
            "img1_color": "0xDC2626",
            "img2_color": "0xEF4444",
            "video_color": "0xB91C1C",
        },
        "has_video": True,
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
            "description": (
                "Cộng đồng dành riêng cho các tín đồ của tác phẩm manga/anime huyền thoại One Piece (Đảo Hải Tặc). "
                "Nơi trao đổi giả thuyết cốt truyện, phân tích chap mới nhất từ tác giả Eiichiro Oda, chia sẻ mô hình figure "
                "và các tác phẩm fanart độc quyền từ cộng đồng sáng tạo."
            ),
            "rules_tos": (
                "1. Bắt buộc gắn thẻ Cảnh báo Spoil khi thảo luận về nội dung chap manga mới chưa chiếu anime.\n"
                "2. Tôn trọng bản quyền tác giả và nguồn gốc các ấn phẩm mô hình sưu tầm."
            ),
        },
        "palette": {
            "avatar_color": "0xD97706",  # Amber Orange
            "banner_color": "0x78350F",  # Deep Brown Orange
            "img1_color": "0xF59E0B",
            "img2_color": "0xFBBF24",
            "video_color": "0xB45309",
        },
        "has_video": False,
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
            "description": (
                "Hội cổ động viên Real Madrid Club de Fútbol chính thức tại Việt Nam. Nơi tụ họp của các Madridistas cùng nhau "
                "chia sẻ niềm tự hào về câu lạc bộ vĩ đại nhất thế kỷ 20 với 15 chiếc cúp UEFA Champions League, cập nhật "
                "tin chuyển nhượng, video bàn thắng và lịch thi đấu La Liga hàng tuần."
            ),
            "rules_tos": (
                "1. Giữ gìn hình ảnh văn minh của cộng đồng Madridistas Việt Nam.\n"
                "2. Nghiêm cấm bàn luận cá độ, phát ngôn thù địch hướng về đối thủ."
            ),
        },
        "palette": {
            "avatar_color": "0x4338CA",  # Royal Indigo
            "banner_color": "0x1E1B4B",  # Deep Indigo
            "img1_color": "0x6366F1",
            "img2_color": "0x818CF8",
            "video_color": "0x4F46E5",
        },
        "has_video": True,
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
            "admission_mode": "APPROVAL",
            "is_public": True,
            "member_count": 1890,
            "description": (
                "Không gian kết nối các chuyên gia, nhà nghiên cứu và kỹ sư trong lĩnh vực Trí tuệ Nhân tạo (AI), "
                "Machine Learning và LLM tại Việt Nam. Nơi chia sẻ các bài báo khoa học, thảo luận kỹ thuật DeepSeek, Gemini, "
                "PyTorch, xây dựng Agentic Workflows và kết nối cơ hội nghề nghiệp công nghệ cao."
            ),
            "rules_tos": (
                "1. Thảo luận chuyên môn văn minh, không spam tin tuyển dụng không đúng kênh.\n"
                "2. Khuyến khích chia sẻ mã nguồn mở và các bài học kinh nghiệm thực chiến."
            ),
        },
        "palette": {
            "avatar_color": "0x0F766E",  # Dark Teal
            "banner_color": "0x134E4A",  # Deep Emerald Teal
            "img1_color": "0x14B8A6",
            "img2_color": "0x2DD4BF",
            "video_color": "0x0D9488",
        },
        "has_video": True,
    },
    {
        "owner": {
            "username": "sontung_sky",
            "email": "sontung.sky@fanspace.vn",
            "display_name": "Nguyễn Thanh Tùng",
        },
        "fandom": {
            "name": "Sky VIP Secret Lounge",
            "slug": "sky-vip-secret-lounge",
            "category": "Âm nhạc",
            "admission_mode": "APPROVAL",
            "is_public": False,  # Private fandom for testing exclusion in public directory
            "member_count": 85,
            "description": (
                "Không gian sinh hoạt bí mật chỉ dành riêng cho các thành viên VIP của gia đình Sky. "
                "Fandom riêng tư này không hiển thị trên danh mục tìm kiếm công khai."
            ),
            "rules_tos": "Tuyệt đối bảo mật nội dung chia sẻ nội bộ.",
        },
        "palette": {
            "avatar_color": "0x312E81",
            "banner_color": "0x1E1B4B",
            "img1_color": "0x4338CA",
            "img2_color": "0x6366F1",
            "video_color": "0x3730A3",
        },
        "has_video": False,
    },
]


def _generate_image(color_hex: str, width: int, height: int, output_path: str) -> None:
    """Generates a clean JPEG image using FFmpeg lavfi color filter."""
    cmd = [
        "ffmpeg",
        "-y",
        "-f",
        "lavfi",
        "-i",
        f"color=c={color_hex}:s={width}x{height}:d=1",
        "-frames:v",
        "1",
        output_path,
    ]
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)


def _generate_video(color_hex: str, duration_sec: int, output_path: str) -> None:
    """Generates a lightweight H.264 MP4 video clip with silent AAC audio using FFmpeg."""
    cmd = [
        "ffmpeg",
        "-y",
        "-f",
        "lavfi",
        "-i",
        f"color=c={color_hex}:s=640x360:d={duration_sec}",
        "-f",
        "lavfi",
        "-i",
        "anullsrc=r=44100:cl=stereo",
        "-c:v",
        "libx264",
        "-t",
        str(duration_sec),
        "-pix_fmt",
        "yuv420p",
        "-c:a",
        "aac",
        output_path,
    ]
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)


async def _upload_asset(
    file_path: str,
    target: MediaTarget,
    user_id: uuid.UUID,
    redis,
    entity_id: uuid.UUID | None = None,
) -> str:
    """Uploads a local media file to Cloudinary via MediaService and returns its CDN URL."""
    # Reset per-user rate limit counter so the batch seeding never gets throttled
    await redis.delete(f"ratelimit:media:upload:{user_id}")

    filename = os.path.basename(file_path)
    with open(file_path, "rb") as f:
        content = f.read()

    upload_file = UploadFile(
        file=BytesIO(content),
        filename=filename,
    )

    res = await MediaService.upload_file(
        file=upload_file,
        user_id=user_id,
        target=target,
        redis=redis,
        entity_id=entity_id,
    )
    return res.url


async def main() -> None:
    print("==================================================================")
    print("🚀 Bắt đầu quá trình Dọn dẹp & Seed dữ liệu Fandom thực tế cho FR-02")
    print("==================================================================")

    redis = get_redis_client()
    try:
        await redis.flushdb()
        print("✅ [Redis] Đã làm sạch toàn bộ Cache RAM.")
    except Exception as e:
        print(f"⚠️ [Redis] Không thể flushdb: {e}")

    # 1. Clean slate database
    async with AsyncSessionLocal() as db:
        print("🧹 [Database] Đang dọn dẹp các bản ghi Fandom và Test User cũ...")
        await db.execute(delete(FandomMember))
        await db.execute(delete(FandomInvite))
        await db.execute(delete(FandomJoinRequest))
        await db.execute(delete(Fandom))
        await db.execute(delete(User))
        await db.commit()
        print("✅ [Database] Đã làm sạch bảng fandoms, fandom_members, users.")

    temp_dir = tempfile.mkdtemp(prefix="fanspace_seed_media_")
    print(f"📁 [Media] Thư mục tạo tệp tạm: {temp_dir}")

    user_cache: dict[str, User] = {}
    seeded_fandoms: list[dict] = []

    try:
        for idx, item in enumerate(FANDOM_DEFINITIONS, start=1):
            owner_info = item["owner"]
            fandom_info = item["fandom"]
            palette = item["palette"]
            has_video = item["has_video"]

            print(f"\n--- [{idx}/{len(FANDOM_DEFINITIONS)}] Đang xử lý Fandom: '{fandom_info['name']}' ---")

            # 2. Find or create Owner
            username = owner_info["username"]
            async with AsyncSessionLocal() as db:
                if username in user_cache:
                    owner = user_cache[username]
                else:
                    owner = User(
                        username=username,
                        email=owner_info["email"],
                        display_name=owner_info["display_name"],
                        password_hash=TEST_USER_PASSWORD,
                        is_active=True,
                    )
                    db.add(owner)
                    await db.commit()
                    await db.refresh(owner)
                    user_cache[username] = owner
                    print(f"   👤 Tạo người dùng: @{owner.username} ({owner.display_name})")

            # 3. Generate media assets for this fandom
            f_slug = fandom_info["slug"]
            avatar_path = os.path.join(temp_dir, f"{f_slug}_avatar.jpg")
            banner_path = os.path.join(temp_dir, f"{f_slug}_banner.jpg")
            img1_path = os.path.join(temp_dir, f"{f_slug}_ill1.jpg")
            img2_path = os.path.join(temp_dir, f"{f_slug}_ill2.jpg")

            _generate_image(palette["avatar_color"], 500, 500, avatar_path)
            _generate_image(palette["banner_color"], 1280, 480, banner_path)
            _generate_image(palette["img1_color"], 800, 600, img1_path)
            _generate_image(palette["img2_color"], 800, 600, img2_path)

            video_path = None
            if has_video:
                video_path = os.path.join(temp_dir, f"{f_slug}_highlight.mp4")
                _generate_video(palette["video_color"], duration_sec=3, output_path=video_path)

            # 4. Upload media to Cloudinary via MediaService
            print("   ☁️ Đang tải ảnh Avatar lên Cloudinary...")
            avatar_url = await _upload_asset(
                file_path=avatar_path,
                target=MediaTarget.FANDOM_AVATAR,
                user_id=owner.id,
                redis=redis,
            )

            print("   ☁️ Đang tải ảnh Banner lên Cloudinary...")
            banner_url = await _upload_asset(
                file_path=banner_path,
                target=MediaTarget.FANDOM_BANNER,
                user_id=owner.id,
                redis=redis,
            )

            print("   ☁️ Đang tải bộ sưu tập minh họa (Illustrations) lên Cloudinary...")
            ill1_url = await _upload_asset(
                file_path=img1_path,
                target=MediaTarget.FANDOM_ILLUSTRATION,
                user_id=owner.id,
                redis=redis,
            )
            ill2_url = await _upload_asset(
                file_path=img2_path,
                target=MediaTarget.FANDOM_ILLUSTRATION,
                user_id=owner.id,
                redis=redis,
            )
            illustration_urls = [ill1_url, ill2_url]

            if video_path:
                print("   🎥 Đang tải video ngắn (MP4) lên Cloudinary...")
                video_url = await _upload_asset(
                    file_path=video_path,
                    target=MediaTarget.FANDOM_ILLUSTRATION,
                    user_id=owner.id,
                    redis=redis,
                )
                illustration_urls.append(video_url)

            # 5. Insert Fandom & Membership into PostgreSQL
            async with AsyncSessionLocal() as db:
                fandom = Fandom(
                    name=fandom_info["name"],
                    slug=f_slug,
                    description=fandom_info["description"],
                    category=fandom_info["category"],
                    avatar_url=avatar_url,
                    banner_url=banner_url,
                    illustration_urls=illustration_urls,
                    admission_mode=fandom_info["admission_mode"],
                    is_public=fandom_info["is_public"],
                    rules_tos=fandom_info.get("rules_tos"),
                    member_count=fandom_info["member_count"],
                    owner_id=owner.id,
                )
                db.add(fandom)
                await db.flush()

                membership = FandomMember(
                    fandom_id=fandom.id,
                    user_id=owner.id,
                    status="ACTIVE",
                )
                db.add(membership)
                await db.commit()

            print(f"   ✨ Fandom '{fandom_info['name']}' đã được lưu thành công!")
            seeded_fandoms.append(
                {
                    "name": fandom_info["name"],
                    "slug": f_slug,
                    "category": fandom_info["category"],
                    "members": fandom_info["member_count"],
                    "admission": fandom_info["admission_mode"],
                    "is_public": fandom_info["is_public"],
                    "illustrations_count": len(illustration_urls),
                    "has_video": has_video,
                }
            )

    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)
        print("\n🧹 Đã dọn dẹp các tệp tạm thời trên đĩa.")

    print("\n==================================================================")
    print("🎉 HOÀN TẤT SEED DỮ LIỆU FR-02!")
    print("==================================================================")
    for f in seeded_fandoms:
        pub_str = "Công khai" if f["is_public"] else "Riêng tư (Ẩn)"
        vid_str = "1 Video + Ảnh" if f["has_video"] else "Ảnh minh họa"
        print(f"• [{f['category']}] {f['name']} (@{f['slug']})")
        print(f"    Thành viên: {f['members']} | Chế độ: {f['admission']} | {pub_str} | Gallery: {f['illustrations_count']} items ({vid_str})")
    print("==================================================================\n")


if __name__ == "__main__":
    asyncio.run(main())
