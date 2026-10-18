from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
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

    # Security & Rate Limiting
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
    return Settings()
