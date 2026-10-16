import pytest
from app.core.database import engine, init_db


@pytest.fixture(autouse=True)
async def setup_and_teardown_db():
    await init_db()
    yield
    await engine.dispose()
