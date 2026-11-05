"""Unit tests for declarative PermissionSpec, PermissionEvaluation, and MockPermissionChecker."""

import uuid
import pytest
from fastapi import HTTPException

from app.core.permissions import (
    MockPermissionChecker,
    Permission,
    PermissionSpec,
)


@pytest.mark.asyncio
async def test_permission_spec_must_have_enforcement():
    """Verifies that all permissions in must_have are required to pass verification."""
    user_id = uuid.uuid4()
    fandom_id = uuid.uuid4()
    channel_id = uuid.uuid4()

    spec = PermissionSpec.of(
        must_have={Permission.VIEW_CHANNEL, Permission.READ_MESSAGES},
    )

    checker_ok = MockPermissionChecker(
        granted={Permission.VIEW_CHANNEL, Permission.READ_MESSAGES}
    )
    evaluation = await checker_ok.verify(user_id, fandom_id, channel_id, spec)
    assert evaluation.has_all(Permission.VIEW_CHANNEL, Permission.READ_MESSAGES) is True

    checker_missing = MockPermissionChecker(granted={Permission.VIEW_CHANNEL})
    with pytest.raises(HTTPException) as exc_info:
        await checker_missing.verify(user_id, fandom_id, channel_id, spec)
    assert exc_info.value.status_code == 403


@pytest.mark.asyncio
async def test_permission_spec_any_of_enforcement():
    """Verifies that at least one permission in any_of is required when specified."""
    user_id = uuid.uuid4()
    fandom_id = uuid.uuid4()
    channel_id = uuid.uuid4()

    spec = PermissionSpec.of(
        must_have={Permission.VIEW_CHANNEL},
        any_of={Permission.SEND_MESSAGES, Permission.SEND_ANNOUNCEMENT},
    )

    checker_one = MockPermissionChecker(
        granted={Permission.VIEW_CHANNEL, Permission.SEND_ANNOUNCEMENT}
    )
    evaluation = await checker_one.verify(user_id, fandom_id, channel_id, spec)
    assert evaluation.has_any(Permission.SEND_MESSAGES, Permission.SEND_ANNOUNCEMENT) is True

    checker_none = MockPermissionChecker(granted={Permission.VIEW_CHANNEL})
    with pytest.raises(HTTPException) as exc_info:
        await checker_none.verify(user_id, fandom_id, channel_id, spec)
    assert exc_info.value.status_code == 403


@pytest.mark.asyncio
async def test_permission_spec_may_have_and_administrator_expansion():
    """Verifies optional may_have capabilities and ADMINISTRATOR full-grant expansion."""
    user_id = uuid.uuid4()
    fandom_id = uuid.uuid4()
    channel_id = uuid.uuid4()

    spec = PermissionSpec.of(
        must_have={Permission.VIEW_CHANNEL},
        may_have={Permission.ATTACH_FILES, Permission.BYPASS_SLOWMODE},
    )

    checker_partial = MockPermissionChecker(
        granted={Permission.VIEW_CHANNEL, Permission.ATTACH_FILES}
    )
    evaluation = await checker_partial.verify(user_id, fandom_id, channel_id, spec)
    assert evaluation.has(Permission.ATTACH_FILES) is True
    assert evaluation.has(Permission.BYPASS_SLOWMODE) is False

    checker_admin = MockPermissionChecker(granted={Permission.ADMINISTRATOR})
    admin_eval = await checker_admin.verify(user_id, fandom_id, channel_id, spec)
    assert admin_eval.has(Permission.VIEW_CHANNEL) is True
    assert admin_eval.has(Permission.ATTACH_FILES) is True
    assert admin_eval.has(Permission.BYPASS_SLOWMODE) is True
    assert admin_eval.has(Permission.MANAGE_CHANNELS) is True
