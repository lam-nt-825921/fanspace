"""Global Application Settings and Environment Configuration.

This module loads and validates environment variables from `.env` using
Pydantic Settings. It defines defaults for security secrets, database pools,
Redis cache, Google OAuth2, and SMTP email delivery.
"""

from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application configuration loaded from environment variables and `.env`.

    Attributes:
        PROJECT_NAME (str): Name of the FastAPI application.
        ENVIRONMENT (str): Deployment environment ('development', 'staging', 'production').
        DEBUG (bool): Flag toggling debug mode and verbose logging.
        PORT (int): HTTP server port.
        SECRET_KEY (str): Secret key for signing JSON Web Tokens.
        ALGORITHM (str): JWT signing algorithm (default 'HS256').
        ACCESS_TOKEN_EXPIRE_MINUTES (int): Lifespan of access tokens in minutes.
        REFRESH_TOKEN_EXPIRE_DAYS (int): Lifespan of refresh tokens in days.
        DATABASE_URL (str): Asyncpg PostgreSQL connection URL.
        DATABASE_POOL_SIZE (int): Maximum persistent connections in the engine pool.
        DATABASE_MAX_OVERFLOW (int): Additional connections allowed beyond pool size.
        REDIS_URL (str): Connection URI for Redis.
        PAYOS_CLIENT_ID (str): Client ID for PayOS payment gateway.
        PAYOS_API_KEY (str): API key for PayOS.
        PAYOS_CHECKSUM_KEY (str): Checksum signing key for PayOS.
        LIVEKIT_URL (str): Host URL for LiveKit WebRTC server.
        LIVEKIT_API_KEY (str): LiveKit API authentication key.
        LIVEKIT_API_SECRET (str): LiveKit API secret.
        GOOGLE_CLIENT_ID (str): Google OAuth2 Web Client ID.
        GOOGLE_CLIENT_SECRET (str): Google OAuth2 Web Client Secret.
        GOOGLE_REDIRECT_URI (str): OAuth2 callback URL.
        SMTP_HOST (str): SMTP server hostname (default 'smtp.gmail.com').
        SMTP_PORT (int): SMTP server port (587 for TLS).
        SMTP_USER (str): Email username/address for SMTP authentication.
        SMTP_PASSWORD (str): SMTP application password.
        EMAILS_FROM_EMAIL (str): Outgoing email address header.
        EMAILS_FROM_NAME (str): Sender display name.
        DEBUG_OTP_IN_RESPONSE (bool): If True, returns `dev_otp` in API responses during dev.
        OTP_TTL_SECONDS (int): Expiration lifespan of OTP codes in seconds (default 300).
        OTP_COOLDOWN_SECONDS (int): Minimum interval between OTP requests in seconds (default 60).
        OTP_MAX_ATTEMPTS (int): Maximum allowed incorrect OTP attempts before revocation (default 5).
        REGISTER_RATE_LIMIT_MAX (int): Maximum registrations allowed per IP in window (default 5).
        REGISTER_RATE_LIMIT_WINDOW (int): Rolling window for register rate limit in seconds (default 600).
        LOGIN_MAX_FAILED_ATTEMPTS (int): Consecutive failed logins before lockout (default 5).
        LOGIN_LOCKOUT_SECONDS (int): Duration of lockout in seconds (default 900 = 15m).
    """

    PROJECT_NAME: str = "FanSpace Backend API"
    ENVIRONMENT: str = "development"
    DEBUG: bool = True
    PORT: int = 8000

    SECRET_KEY: str = "fanspace-super-secret-scientific-benchmark-key-change-in-prod"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7

    DATABASE_URL: str = "postgresql+asyncpg://fanspace:fanspace_password@localhost:5433/fanspace_db"
    DATABASE_POOL_SIZE: int = 15
    DATABASE_MAX_OVERFLOW: int = 5

    REDIS_URL: str = "redis://localhost:6379/0"

    PAYOS_CLIENT_ID: str = ""
    PAYOS_API_KEY: str = ""
    PAYOS_CHECKSUM_KEY: str = ""

    LIVEKIT_URL: str = ""
    LIVEKIT_API_KEY: str = ""
    LIVEKIT_API_SECRET: str = ""

    # Google OAuth2
    GOOGLE_CLIENT_ID: str = ""
    GOOGLE_CLIENT_SECRET: str = ""
    GOOGLE_REDIRECT_URI: str = "http://localhost:8000/api/v1/auth/google/callback"

    # SMTP Mailer (e.g. Gmail SMTP)
    SMTP_HOST: str = "smtp.gmail.com"
    SMTP_PORT: int = 587
    SMTP_USER: str = ""
    SMTP_PASSWORD: str = ""
    EMAILS_FROM_EMAIL: str = ""
    EMAILS_FROM_NAME: str = "FanSpace Security"
    DEBUG_OTP_IN_RESPONSE: bool = True

    # Cloudinary Media Storage & Upload Quotas
    CLOUDINARY_CLOUD_NAME: str = ""
    CLOUDINARY_API_KEY: str = ""
    CLOUDINARY_API_SECRET: str = ""
    MEDIA_MAX_AVATAR_BYTES: int = 2 * 1024 * 1024  # 2 MB max for user/fandom avatars
    MEDIA_MAX_BANNER_BYTES: int = 5 * 1024 * 1024  # 5 MB max for user/fandom banners
    MEDIA_MAX_IMAGE_BYTES: int = 5 * 1024 * 1024  # 5 MB max for general/illustration images
    MEDIA_MAX_VIDEO_BYTES: int = 15 * 1024 * 1024  # 15 MB max for short videos
    MEDIA_MAX_VIDEO_DURATION_SECONDS: float = 60.0  # 60s max duration for short clips
    MEDIA_MAX_ILLUSTRATION_COUNT: int = 5  # Max 5 media items per fandom profile
    MEDIA_MAX_ILLUSTRATION_VIDEOS: int = 1  # Max 1 short video in fandom illustrations
    MEDIA_UPLOAD_RATE_LIMIT_MAX: int = 10  # Max 10 uploads per user per minute
    MEDIA_UPLOAD_RATE_LIMIT_WINDOW: int = 60  # 60 seconds window

    # Security & Rate Limiting
    PENDING_REGISTRATION_TTL_SECONDS: int = 600  # 10 minutes auto-cancel for unverified registration
    OTP_TTL_SECONDS: int = 300  # 5 minutes
    OTP_COOLDOWN_SECONDS: int = 60  # 1 minute
    OTP_MAX_ATTEMPTS: int = 5
    REGISTER_RATE_LIMIT_MAX: int = 5
    REGISTER_RATE_LIMIT_WINDOW: int = 600  # 10 minutes
    LOGIN_MAX_FAILED_ATTEMPTS: int = 5
    LOGIN_LOCKOUT_SECONDS: int = 900  # 15 minutes

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore"
    )


@lru_cache()
def get_settings() -> Settings:
    """Returns a cached singleton instance of the application Settings.

    Returns:
        Settings: Initialized configuration object.
    """
    return Settings()
