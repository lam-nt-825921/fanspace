"""FanSpace Backend Application Entry Point.

This module sets up the FastAPI application wrapped with python-socketio ASGI server.
It defines lifespan lifecycle events (database and Redis pool initialization),
configures Cross-Origin Resource Sharing (CORS), mounts modular monolith routers,
and publishes OpenAPI / Swagger metadata.
"""

from contextlib import asynccontextmanager
import socketio
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text

from app.core.config import get_settings
from app.core.database import engine, init_db
from app.core.redis import redis_client
from app.modules.identity.router import auth_router, users_router
from app.modules.fandom.router import fandom_router
from app.modules.media.router import media_router

settings = get_settings()

tags_metadata = [
    {
        "name": "Authentication & Identity",
        "description": "Các API xác thực, đăng ký, đăng nhập đa nền tảng, Google OAuth2, xác thực Email qua OTP (Redis), "
                       "cấp mật khẩu cho tài khoản mạng xã hội, quản lý phiên và thu hồi phiên từ xa.",
    },
    {
        "name": "Users",
        "description": "Quản lý hồ sơ người dùng cá nhân, trạng thái định danh và thông tin xác thực.",
    },
    {
        "name": "Fandoms",
        "description": "Khởi tạo, tìm kiếm và khám phá các cộng đồng người hâm mộ (Fandom) công khai.",
    },
    {
        "name": "Media",
        "description": "Tải lên, kiểm duyệt định dạng và dọn dẹp tệp phương tiện (Ảnh / Short Video) trên Cloudinary CDN.",
    },
    {
        "name": "System",
        "description": "Kiểm tra sức khỏe hệ thống (Health Check) và kết nối cơ sở hạ tầng (PostgreSQL, Redis).",
    },
]

# Initialize Socket.IO Server
sio = socketio.AsyncServer(
    async_mode="asgi",
    cors_allowed_origins="*",
    logger=settings.DEBUG,
    engineio_logger=False,
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manages the startup and shutdown lifecycles of the application.

    On startup:
        Initializes PostgreSQL tables and applies idempotent column migrations.
    On shutdown:
        Disposes of database connection pools and closes Redis connections.

    Args:
        app (FastAPI): The running FastAPI instance.
    """
    # Startup: Initialize DB tables & connections
    await init_db()
    yield
    # Shutdown: Clean up connections
    await engine.dispose()
    await redis_client.aclose()


app = FastAPI(
    title=settings.PROJECT_NAME,
    version="1.0.0",
    description="""
    # FanSpace Backend API - Mạng Xã Hội Fandom & Giao Tiếp Thời Gian Thực

    Hệ thống Backend được xây dựng theo kiến trúc **Modular Monolith** chuẩn bảo mật cao:
    - **Authentication & Identity**: Đăng ký, đăng nhập bảo vệ bằng Argon2id, Google OAuth2, xác thực Email qua OTP (Redis 5m TTL).
    - **Single Platform Session**: Giới hạn tối đa 1 phiên hoạt động cho mỗi nền tảng (`MOBILE`, `DESKTOP`, `WEB`).
    - **Security & Rate Limiting**: Chống brute-force đăng nhập (khóa 15 phút sau 5 lần sai), rate limit đăng ký theo IP, và Refresh Token Rotation tuân thủ RFC 7519 (`jti`).
    - **Fandom Core**: Khởi tạo và khám phá cộng đồng người hâm mộ với slug tùy chỉnh và quản lý thành viên.
    - **Shared Media Storage**: Tải lên và quản lý vòng đời ảnh/short video qua Cloudinary CDN.
    """,
    openapi_tags=tags_metadata,
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc",
)

# CORS Middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount Routers
app.include_router(auth_router)
app.include_router(users_router)
app.include_router(fandom_router)
app.include_router(media_router)


@app.get(
    "/health",
    tags=["System"],
    summary="Kiểm tra trạng thái sức khỏe hệ thống (Health Check)",
    description="Kiểm tra kết nối trực tiếp tới cơ sở dữ liệu PostgreSQL và Redis cache.",
)
async def health_check():
    """Validates connectivity to PostgreSQL and Redis infrastructure components.

    Returns:
        dict: Operational statuses of database, cache, environment, and project name.
    """
    db_status = "disconnected"
    redis_status = "disconnected"

    # Test DB
    try:
        async with engine.connect() as conn:
            await conn.execute(text("SELECT 1"))
            db_status = "connected"
    except Exception as e:
        db_status = f"error: {str(e)}"

    # Test Redis
    try:
        if await redis_client.ping():
            redis_status = "connected"
    except Exception as e:
        redis_status = f"error: {str(e)}"

    is_healthy = db_status == "connected" and redis_status == "connected"

    return {
        "status": "healthy" if is_healthy else "degraded",
        "database": db_status,
        "redis": redis_status,
        "environment": settings.ENVIRONMENT,
        "project": settings.PROJECT_NAME,
    }


# Socket.IO Event Handlers
@sio.event
async def connect(sid: str, environ: dict, auth: dict | None = None) -> bool:
    """Socket.IO connection handshake event handler.

    Args:
        sid (str): Socket connection ID.
        environ (dict): ASGI environment dictionary.
        auth (dict | None): Authentication credentials sent in handshake.

    Returns:
        bool: True to accept the connection.
    """
    return True


@sio.event
async def disconnect(sid: str) -> None:
    """Socket.IO disconnection cleanup event handler.

    Args:
        sid (str): Socket connection ID that disconnected.
    """
    pass


# Wrap FastAPI with Socket.IO ASGI app
socket_app = socketio.ASGIApp(sio, other_asgi_app=app)
