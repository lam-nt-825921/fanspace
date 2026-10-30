"""Database Engine, Session Factory, and Schema Initializer.

This module initializes the SQLAlchemy asynchronous engine with asyncpg, configures
the scoped session maker, and provides automatic idempotent schema migrations
for development and production environments.
"""

from collections.abc import AsyncGenerator
from sqlalchemy import text
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase

from app.core.config import get_settings

settings = get_settings()

engine = create_async_engine(
    settings.DATABASE_URL,
    echo=settings.DEBUG,
    pool_size=settings.DATABASE_POOL_SIZE,
    max_overflow=settings.DATABASE_MAX_OVERFLOW,
    pool_pre_ping=True,
)

AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autocommit=False,
    autoflush=False,
)


class Base(DeclarativeBase):
    """Declarative Base class for all SQLAlchemy ORM models."""
    pass


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """Dependency providing an asynchronous database session.

    Yields:
        AsyncSession: Scoped database session that automatically closes upon exit.
    """
    async with AsyncSessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()


async def init_db() -> None:
    """Initializes tables, PostgreSQL extensions, and idempotent schema/index migrations.

    Configures `unaccent` and `pg_trgm` extensions, defines the immutable `f_unaccent`
    normalization function (handling Vietnamese 'đ/Đ'), and creates composite B-Tree
    and GIN trigram indexes for high-concurrency fandom discovery.
    """
    import app.models  # noqa: F401
    async with engine.begin() as conn:
        await conn.execute(text("CREATE EXTENSION IF NOT EXISTS unaccent;"))
        await conn.execute(text("CREATE EXTENSION IF NOT EXISTS pg_trgm;"))
        await conn.execute(
            text(
                """
                CREATE OR REPLACE FUNCTION f_unaccent(text)
                RETURNS text AS $$
                    SELECT translate(public.unaccent('public.unaccent', coalesce($1, '')), 'đĐ', 'dD');
                $$ LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT;
                """
            )
        )
        await conn.run_sync(Base.metadata.create_all)
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS system_role VARCHAR(50) DEFAULT 'USER' NOT NULL;"))
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT TRUE NOT NULL;"))
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE NULL;"))
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS banner_url TEXT NULL;"))
        await conn.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS ix_users_google_id ON users (google_id);"))

        # Fandom public discovery columns and high-concurrency indexes (FR-02: 10,000 CCU)
        await conn.execute(text("ALTER TABLE fandoms ADD COLUMN IF NOT EXISTS is_public BOOLEAN DEFAULT TRUE NOT NULL;"))
        await conn.execute(text("CREATE INDEX IF NOT EXISTS ix_fandoms_owner_id ON fandoms (owner_id);"))
        await conn.execute(
            text("CREATE INDEX IF NOT EXISTS ix_fandoms_public_popular ON fandoms (is_public, member_count DESC, created_at DESC);")
        )
        await conn.execute(
            text("CREATE INDEX IF NOT EXISTS ix_fandoms_public_cat_popular ON fandoms (is_public, category, member_count DESC, created_at DESC);")
        )
        await conn.execute(
            text("CREATE INDEX IF NOT EXISTS ix_fandoms_public_newest ON fandoms (is_public, created_at DESC);")
        )
        await conn.execute(
            text("CREATE INDEX IF NOT EXISTS ix_fandoms_public_name_asc ON fandoms (is_public, name ASC);")
        )
        await conn.execute(
            text("CREATE INDEX IF NOT EXISTS ix_fandom_members_fandom_user_active ON fandom_members (fandom_id, user_id, status);")
        )

        # GIN Trigram indexes for accent-insensitive and case-insensitive search
        await conn.execute(
            text("CREATE INDEX IF NOT EXISTS ix_fandoms_name_trgm ON fandoms USING gin (f_unaccent(lower(name)) gin_trgm_ops);")
        )
        await conn.execute(
            text("CREATE INDEX IF NOT EXISTS ix_fandoms_slug_trgm ON fandoms USING gin (lower(slug) gin_trgm_ops);")
        )
        await conn.execute(
            text("CREATE INDEX IF NOT EXISTS ix_users_display_name_trgm ON users USING gin (f_unaccent(lower(display_name)) gin_trgm_ops);")
        )
        await conn.execute(
            text("CREATE INDEX IF NOT EXISTS ix_users_username_trgm ON users USING gin (lower(username) gin_trgm_ops);")
        )
