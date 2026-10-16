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

settings = get_settings()

# Initialize Socket.IO Server
sio = socketio.AsyncServer(
    async_mode="asgi",
    cors_allowed_origins="*",
    logger=settings.DEBUG,
    engineio_logger=False
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: Initialize DB tables & connections
    await init_db()
    yield
    # Shutdown: Clean up connections
    await engine.dispose()
    await redis_client.aclose()


app = FastAPI(
    title=settings.PROJECT_NAME,
    version="1.0.0",
    description="FanSpace Backend API - Modular Monolith Architecture",
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc"
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



@app.get("/health", tags=["System"])
async def health_check():
    """Health check endpoint validating PostgreSQL and Redis connectivity"""
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
        "project": settings.PROJECT_NAME
    }


# Socket.IO Event Handlers
@sio.event
async def connect(sid, environ, auth):
    # Handshake Auth will be hooked here
    return True


@sio.event
async def disconnect(sid):
    pass


# Wrap FastAPI with Socket.IO ASGI app
socket_app = socketio.ASGIApp(sio, other_asgi_app=app)
