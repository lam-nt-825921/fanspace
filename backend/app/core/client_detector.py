"""Client and Device Detection Module.

This module provides tools to accurately extract client networking and hardware
fingerprints from incoming HTTP requests. It prioritizes reverse-proxy headers
(Cloudflare, Nginx) and parses User-Agent strings using `user_agents` to distinguish
between mobile devices, desktop platforms, and standard web browsers.
"""

from dataclasses import dataclass
from fastapi import Request, HTTPException, status
import user_agents


@dataclass
class ClientInfo:
    """Encapsulates client metadata parsed from an HTTP request.

    Attributes:
        ip_address (str): Resolved IP address of the client (IPv4 or IPv6).
        platform (str): Operating platform ('MOBILE', 'DESKTOP', or 'WEB').
        device_id (str | None): Unique hardware/client identifier (mandatory for MOBILE).
        device_name (str): Human-readable device and OS identification.
        user_agent (str): Full raw User-Agent header string.
    """
    ip_address: str
    platform: str
    device_id: str | None
    device_name: str
    user_agent: str


def extract_client_info(
    request: Request,
    explicit_platform: str | None = None,
    explicit_device_id: str | None = None,
) -> ClientInfo:
    """Extracts client IP, platform type, and device metadata from an HTTP request.

    Resolves the client's true IP by inspecting reverse proxy headers in order:
    1. 'cf-connecting-ip' (Cloudflare)
    2. 'x-forwarded-for' (First non-trusted proxy entry)
    3. 'x-real-ip' (Nginx)
    4. Fallback to `request.client.host`.

    Validates that client platform is one of ('MOBILE', 'DESKTOP', 'WEB').
    Enforces the business rule that mobile applications MUST provide a unique `device_id`.

    Args:
        request (Request): FastAPI request object containing headers and client info.
        explicit_platform (str | None, optional): Platform string provided in payload.
        explicit_device_id (str | None, optional): Device ID string provided in payload.

    Returns:
        ClientInfo: Structured dataclass with client IP, platform, device ID, and name.

    Raises:
        HTTPException: 400 Bad Request if platform is 'MOBILE' but no device_id is provided.
    """
    headers = request.headers

    # 1. IP extraction
    ip_address = (
        headers.get("cf-connecting-ip")
        or (headers.get("x-forwarded-for").split(",")[0].strip() if headers.get("x-forwarded-for") else None)
        or headers.get("x-real-ip")
        or (request.client.host if request.client else "127.0.0.1")
    )

    # 2. User Agent & Device Name
    ua_str = headers.get("user-agent", "Unknown Client")
    try:
        ua = user_agents.parse(ua_str)
        browser_info = f"{ua.browser.family} {ua.browser.version_string}".strip()
        os_info = f"{ua.os.family} {ua.os.version_string}".strip()
        if ua.device.family and ua.device.family != "Other":
            device_name = f"{ua.device.family} ({os_info})"
        elif browser_info and os_info:
            device_name = f"{browser_info} on {os_info}"
        else:
            device_name = ua_str[:100]
    except Exception:
        device_name = ua_str[:100]

    # 3. Platform determination
    header_platform = headers.get("x-platform")
    raw_platform = explicit_platform or header_platform
    if raw_platform:
        platform = raw_platform.strip().upper()
    else:
        platform = "WEB"

    if platform not in ("MOBILE", "DESKTOP", "WEB"):
        platform = "WEB"

    # 4. Device ID
    header_device_id = headers.get("x-device-id")
    device_id = explicit_device_id or header_device_id

    # Rule: Mobile app requires device_id
    if platform == "MOBILE" and not device_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Phiên đăng nhập trên ứng dụng di động (MOBILE) bắt buộc phải có mã định danh thiết bị (device_id hoặc header X-Device-Id).",
        )

    return ClientInfo(
        ip_address=ip_address,
        platform=platform,
        device_id=device_id,
        device_name=device_name[:150],
        user_agent=ua_str[:500],
    )
