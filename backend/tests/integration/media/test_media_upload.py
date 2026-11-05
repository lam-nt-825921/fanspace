"""Integration and unit tests for the Shared Media Upload & Cloudinary Lifecycle Service.

Covers:
- Magic-byte file signature inspection (rejecting spoofed file extensions and empty files).
- Target-specific size quotas (2 MB for avatars, 5 MB for banners/images, 15 MB for short videos)
  and video duration enforcement (max 60s).
- Deterministic `public_id` with `overwrite=True` for single-value assets (`USER_AVATAR`, `USER_BANNER`,
  `FANDOM_AVATAR`, `FANDOM_BANNER`).
- Fandom illustration constraints (max 5 items, max 1 short video).
- Background orphan cleanup (`cleanup_replaced_urls`, `delete_by_url` for both image and video,
  ownership authorization on `DELETE /api/v1/media`, and skipping external OAuth URLs).
- Per-user Redis upload rate limiting (max 10 uploads/minute).
- Live Cloudinary API connectivity (`ping`) and real upload + destroy round-trip verification.
"""

import uuid
from unittest.mock import patch
import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app
from app.core.config import get_settings
from app.core.redis import get_redis_client
from app.modules.media.schemas import MediaResourceType, MediaTarget
from app.modules.media.service import MediaService

settings = get_settings()

# Minimal valid binary headers (Magic Bytes) for supported media formats
VALID_PNG_BYTES = (
    b"\x89PNG\r\n\x1a\n"
    b"\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89"
    b"\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82"
)
VALID_JPEG_BYTES = b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00\xff\xd9"
VALID_WEBP_BYTES = b"RIFF\x1a\x00\x00\x00WEBPVP8 \x0e\x00\x00\x00\x30\x01\x00\x9d\x01\x2a\x01\x00\x01\x00\x00\x00"
VALID_MP4_BYTES = b"\x00\x00\x00\x18ftypmp42\x00\x00\x00\x00mp42isom\x00\x00\x00\x08free"


async def _create_authenticated_user(client: AsyncClient) -> tuple[dict, str]:
    """Registers and verifies a test user, returning `(user_dict, access_token)`."""
    uid = uuid.uuid4().hex[:8]
    email = f"media_user_{uid}@example.com"
    reg_res = await client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "username": f"media_{uid}",
            "password": "StrongPassword123!",
            "display_name": "Media Tester",
        },
    )
    assert reg_res.status_code == 202
    otp_code = reg_res.json()["dev_otp"]

    verify_res = await client.post(
        "/api/v1/auth/email/verify-otp",
        json={"email": email, "code": otp_code, "purpose": "VERIFY_EMAIL"},
    )
    assert verify_res.status_code == 200
    data = verify_res.json()
    return data["user"], data["tokens"]["access_token"]


# ==============================================================================
# 1. AUTHENTICATION, MAGIC BYTES & SIZE QUOTA VALIDATION
# ==============================================================================


@pytest.mark.asyncio
async def test_media_upload_validation_and_quotas(monkeypatch):
    """Rejects unauthenticated uploads, spoofed MIME headers, disallowed video targets, and oversized payloads."""
    transport = ASGITransport(app=app)

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        user, token = await _create_authenticated_user(client)
        headers = {"Authorization": f"Bearer {token}"}

        # 1. Unauthenticated upload request -> 401
        unauth_res = await client.post(
            "/api/v1/media/upload",
            files={"file": ("avatar.png", VALID_PNG_BYTES, "image/png")},
            data={"target": "USER_AVATAR"},
        )
        assert unauth_res.status_code == 401

        # 2. Empty file -> 400
        empty_res = await client.post(
            "/api/v1/media/upload",
            headers=headers,
            files={"file": ("empty.png", b"", "image/png")},
            data={"target": "USER_AVATAR"},
        )
        assert empty_res.status_code == 400

        # 3. Spoofed file extension (.jpg containing executable/HTML script bytes) -> 400
        spoofed_res = await client.post(
            "/api/v1/media/upload",
            headers=headers,
            files={"file": (" fake_image.jpg", b"<html><script>alert(1)</script></html>", "image/jpeg")},
            data={"target": "USER_AVATAR"},
        )
        assert spoofed_res.status_code == 400
        assert "Định dạng tệp không được hỗ trợ" in spoofed_res.json()["detail"]

        # 4. Uploading MP4 video to image-only target (USER_AVATAR) -> 400
        video_on_avatar_res = await client.post(
            "/api/v1/media/upload",
            headers=headers,
            files={"file": ("clip.mp4", VALID_MP4_BYTES, "video/mp4")},
            data={"target": "USER_AVATAR"},
        )
        assert video_on_avatar_res.status_code == 400
        assert "chỉ chấp nhận tệp hình ảnh" in video_on_avatar_res.json()["detail"]

        # 5. Oversized avatar (> 2 MB) -> 413 Request Entity Too Large
        monkeypatch.setattr(settings, "MEDIA_MAX_AVATAR_BYTES", 1024)  # 1 KB limit for test speed
        oversized_avatar = VALID_JPEG_BYTES + (b"\x00" * 2048)
        over_res = await client.post(
            "/api/v1/media/upload",
            headers=headers,
            files={"file": ("large.jpg", oversized_avatar, "image/jpeg")},
            data={"target": "USER_AVATAR"},
        )
        assert over_res.status_code == 413


# ==============================================================================
# 2. DETERMINISTIC OVERWRITE, SHORT VIDEO UPLOAD & DURATION ENFORCEMENT
# ==============================================================================


@pytest.mark.asyncio
async def test_media_upload_image_and_short_video_with_mocked_cloudinary():
    """Verifies deterministic public_id overwrite for avatars and thumbnail generation / duration limits for short videos."""
    transport = ASGITransport(app=app)

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        user, token = await _create_authenticated_user(client)
        user_id = user["id"]
        headers = {"Authorization": f"Bearer {token}"}

        # 1. Upload USER_AVATAR -> deterministic public_id with overwrite=True
        expected_public_id = f"fanspace/users/{user_id}/avatar"
        with patch("cloudinary.uploader.upload") as mock_upload:
            mock_upload.return_value = {
                "secure_url": f"https://res.cloudinary.com/{settings.CLOUDINARY_CLOUD_NAME}/image/upload/v1730000001/{expected_public_id}.webp",
                "public_id": expected_public_id,
                "format": "webp",
                "bytes": len(VALID_WEBP_BYTES),
                "width": 512,
                "height": 512,
            }
            res_avatar = await client.post(
                "/api/v1/media/upload",
                headers=headers,
                files={"file": ("avatar.webp", VALID_WEBP_BYTES, "image/webp")},
                data={"target": "USER_AVATAR"},
            )
            assert res_avatar.status_code == 201
            body = res_avatar.json()
            assert body["public_id"] == expected_public_id
            assert body["resource_type"] == "image"
            assert body["thumbnail_url"] is None

            # Ensure overwrite=True and invalidate=True were passed to Cloudinary
            _, kwargs = mock_upload.call_args
            assert kwargs["public_id"] == expected_public_id
            assert kwargs["overwrite"] is True
            assert kwargs["invalidate"] is True

        # 2. Upload Short Video for FANDOM_ILLUSTRATION -> returns video URL + auto-derived thumbnail_url
        fandom_id = str(uuid.uuid4())
        with patch("cloudinary.uploader.upload") as mock_upload:
            mock_upload.return_value = {
                "secure_url": f"https://res.cloudinary.com/{settings.CLOUDINARY_CLOUD_NAME}/video/upload/v1730000002/fanspace/fandoms/{fandom_id}/illustrations/clip123.mp4",
                "public_id": f"fanspace/fandoms/{fandom_id}/illustrations/clip123",
                "format": "mp4",
                "bytes": len(VALID_MP4_BYTES),
                "width": 1280,
                "height": 720,
                "duration": 18.5,
            }
            res_video = await client.post(
                "/api/v1/media/upload",
                headers=headers,
                files={"file": ("intro.mp4", VALID_MP4_BYTES, "video/mp4")},
                data={"target": "FANDOM_ILLUSTRATION", "entity_id": fandom_id},
            )
            assert res_video.status_code == 201
            v_body = res_video.json()
            assert v_body["resource_type"] == "video"
            assert v_body["duration"] == 18.5
            assert v_body["thumbnail_url"].endswith("/illustrations/clip123.jpg")
            assert "/video/upload/so_1/" in v_body["thumbnail_url"]

        # 3. Short Video exceeding 60s duration is immediately destroyed and rejected with 400
        with (
            patch("cloudinary.uploader.upload") as mock_upload,
            patch("cloudinary.uploader.destroy") as mock_destroy,
        ):
            mock_upload.return_value = {
                "secure_url": f"https://res.cloudinary.com/{settings.CLOUDINARY_CLOUD_NAME}/video/upload/v1730000003/fanspace/fandoms/{fandom_id}/illustrations/longclip.mp4",
                "public_id": f"fanspace/fandoms/{fandom_id}/illustrations/longclip",
                "format": "mp4",
                "bytes": len(VALID_MP4_BYTES),
                "duration": 125.0,
            }
            mock_destroy.return_value = {"result": "ok"}

            res_long = await client.post(
                "/api/v1/media/upload",
                headers=headers,
                files={"file": ("long.mp4", VALID_MP4_BYTES, "video/mp4")},
                data={"target": "FANDOM_ILLUSTRATION", "entity_id": fandom_id},
            )
            assert res_long.status_code == 400
            assert "Thời lượng video vượt quá giới hạn" in res_long.json()["detail"]
            mock_destroy.assert_called_once_with(
                f"fanspace/fandoms/{fandom_id}/illustrations/longclip",
                resource_type="video",
                invalidate=True,
            )


# ==============================================================================
# 3. ORPHAN ASSET CLEANUP & ILLUSTRATION QUOTA VALIDATION
# ==============================================================================


@pytest.mark.asyncio
async def test_media_orphan_cleanup_and_ownership_authorization():
    """Verifies URL extraction, background cleanup of replaced assets, and ownership checks on DELETE /api/v1/media."""
    cloud = settings.CLOUDINARY_CLOUD_NAME or "djioawkmo"
    img_url_1 = f"https://res.cloudinary.com/{cloud}/image/upload/v1730000001/fanspace/fandoms/f1/illustrations/img1.webp"
    img_url_2 = f"https://res.cloudinary.com/{cloud}/image/upload/v1730000001/fanspace/fandoms/f1/illustrations/img2.png"
    vid_url_1 = f"https://res.cloudinary.com/{cloud}/video/upload/v1730000001/fanspace/fandoms/f1/illustrations/vid1.mp4"
    google_avatar = "https://lh3.googleusercontent.com/a/default-user"

    # 1. External Google avatar URL is safely ignored
    assert MediaService.extract_cloudinary_asset_info(google_avatar) is None

    # 2. Cleanup replaced URLs destroys only removed items with their matching resource_type
    with patch("cloudinary.uploader.destroy", return_value={"result": "ok"}) as mock_destroy:
        await MediaService.cleanup_replaced_urls(
            old_urls=[img_url_1, img_url_2, vid_url_1, google_avatar],
            new_urls=[img_url_1],  # img_url_2 and vid_url_1 were removed
        )
        assert mock_destroy.call_count == 2
        calls = [(c.args[0], c.kwargs["resource_type"]) for c in mock_destroy.call_args_list]
        assert ("fanspace/fandoms/f1/illustrations/img2", "image") in calls
        assert ("fanspace/fandoms/f1/illustrations/vid1", "video") in calls

    # 3. Illustration URL list validation (max 5 items, max 1 video)
    valid_list = MediaService.validate_illustration_urls([img_url_1, img_url_2, vid_url_1])
    assert len(valid_list) == 3

    with pytest.raises(Exception) as exc_too_many:
        MediaService.validate_illustration_urls([img_url_1] * 6)
    assert exc_too_many.value.status_code == 400

    with pytest.raises(Exception) as exc_two_videos:
        MediaService.validate_illustration_urls([vid_url_1, vid_url_1])
    assert exc_two_videos.value.status_code == 400

    # 4. DELETE /api/v1/media ownership enforcement
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        user_a, token_a = await _create_authenticated_user(client)
        user_b, _ = await _create_authenticated_user(client)

        user_b_asset = f"https://res.cloudinary.com/{cloud}/image/upload/v1730000001/fanspace/users/{user_b['id']}/avatar.webp"
        forbidden_res = await client.request(
            "DELETE",
            "/api/v1/media",
            headers={"Authorization": f"Bearer {token_a}"},
            json={"url": user_b_asset},
        )
        assert forbidden_res.status_code == 403


# ==============================================================================
# 4. PER-USER UPLOAD RATE LIMITING
# ==============================================================================


@pytest.mark.asyncio
async def test_media_upload_rate_limit(monkeypatch):
    """Enforces per-user upload rate limits on Redis and returns 429 when exceeded."""
    monkeypatch.setattr(settings, "MEDIA_UPLOAD_RATE_LIMIT_MAX", 3)
    transport = ASGITransport(app=app)

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        user, token = await _create_authenticated_user(client)
        headers = {"Authorization": f"Bearer {token}"}

        with patch("cloudinary.uploader.upload") as mock_upload:
            mock_upload.return_value = {
                "secure_url": f"https://res.cloudinary.com/{settings.CLOUDINARY_CLOUD_NAME}/image/upload/v1/fanspace/users/{user['id']}/avatar.png",
                "public_id": f"fanspace/users/{user['id']}/avatar",
                "format": "png",
                "bytes": len(VALID_PNG_BYTES),
            }
            for _ in range(3):
                ok_res = await client.post(
                    "/api/v1/media/upload",
                    headers=headers,
                    files={"file": ("a.png", VALID_PNG_BYTES, "image/png")},
                    data={"target": "USER_AVATAR"},
                )
                assert ok_res.status_code == 201

            # 4th upload within the 60s window -> 429 Too Many Requests
            limited_res = await client.post(
                "/api/v1/media/upload",
                headers=headers,
                files={"file": ("a.png", VALID_PNG_BYTES, "image/png")},
                data={"target": "USER_AVATAR"},
            )
            assert limited_res.status_code == 429

        r = get_redis_client()
        await r.delete(f"ratelimit:media:upload:{user['id']}")


# ==============================================================================
# 5. LIVE CLOUDINARY CONNECTION & ROUND-TRIP UPLOAD / DESTROY VERIFICATION
# ==============================================================================


@pytest.mark.asyncio
async def test_cloudinary_live_ping_and_roundtrip_upload_destroy():
    """Verifies live connection to Cloudinary, uploads a real test image, and immediately deletes it."""
    if (
        not settings.CLOUDINARY_CLOUD_NAME
        or not settings.CLOUDINARY_API_KEY
        or not settings.CLOUDINARY_API_SECRET
    ):
        pytest.skip("Cloudinary credentials are not configured in .env")

    # 1. Verify live ping
    assert await MediaService.ping_cloudinary() is True

    # 2. Perform a real upload + immediate delete round-trip through the FastAPI endpoint
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        user, token = await _create_authenticated_user(client)
        headers = {"Authorization": f"Bearer {token}"}

        upload_res = await client.post(
            "/api/v1/media/upload",
            headers=headers,
            files={"file": ("live_test.png", VALID_PNG_BYTES, "image/png")},
            data={"target": "USER_AVATAR"},
        )
        assert upload_res.status_code == 201
        uploaded = upload_res.json()
        assert uploaded["url"].startswith(f"https://res.cloudinary.com/{settings.CLOUDINARY_CLOUD_NAME}/image/upload/")
        assert uploaded["public_id"] == f"fanspace/users/{user['id']}/avatar"

        # 3. Clean up the uploaded test asset from Cloudinary
        del_res = await client.request(
            "DELETE",
            "/api/v1/media",
            headers=headers,
            json={"url": uploaded["url"]},
        )
        assert del_res.status_code == 200
        assert del_res.json()["success"] is True
