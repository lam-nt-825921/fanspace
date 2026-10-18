import pytest
from app.core.database import engine, init_db
from app.core.redis import reset_redis_client, get_redis_client


@pytest.fixture(autouse=True)
async def setup_and_teardown_db():
    await init_db()
    r = get_redis_client()
    try:
        await r.flushdb()
    except Exception:
        pass
    yield
    await engine.dispose()
    await reset_redis_client()
