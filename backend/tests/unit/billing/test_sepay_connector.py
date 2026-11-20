"""Unit tests for the SePay Account Activation Connector (`sepay_connector.py`).

Verifies the isolated adapter pattern for SePay account activation:
1. Sandbox token matching against pre-registered SePay Sandbox bank accounts.
2. Graceful simulation for unlisted sandbox account numbers.
3. Resilient offline fallback when network is unavailable.
4. OAuth connector stub isolation and factory mode selection.
"""

import uuid
from unittest.mock import AsyncMock, patch
import pytest

from app.modules.billing.sepay_connector import (
    BaseSePayAccountConnector,
    SePayAccountActivationResult,
    SePayOAuthConnector,
    SePaySandboxTokenConnector,
    get_sepay_account_connector,
)


@pytest.mark.asyncio
async def test_sepay_sandbox_connector_matched_account():
    """Verifies that an account number matching a SePay Sandbox account is verified and linked."""
    connector = SePaySandboxTokenConnector(
        api_key="S8VBIOJLZ237NGR3VAMYD5X51MPSDV2QXABYGUAZHX9ROPLTE7DKQ810Y90FHILP"
    )

    fandom_id = uuid.uuid4()
    # 6280793157 is pre-registered on user's SePay Sandbox as MBBank - NGUYEN TUNG LAM
    res = await connector.activate_bank_account(
        bank_code="MBBank",
        account_number="6280793157",
        account_name="NGUYEN TUNG LAM",
        fandom_id=fandom_id,
    )

    assert res.success is True
    assert res.is_verified is True
    assert res.activation_mode == "sandbox_token"
    assert res.sepay_account_id == "4873ef39-e3e6-11f1-8895-0afffe87053b"
    assert "MBBank" in res.activation_note
    assert "NGUYEN TUNG LAM" in res.activation_note


@pytest.mark.asyncio
async def test_sepay_sandbox_connector_unmatched_simulated_account():
    """Verifies that a bank account not yet in the sandbox registry activates in simulated sandbox mode."""
    connector = SePaySandboxTokenConnector(
        api_key="S8VBIOJLZ237NGR3VAMYD5X51MPSDV2QXABYGUAZHX9ROPLTE7DKQ810Y90FHILP"
    )

    fandom_id = uuid.uuid4()
    res = await connector.activate_bank_account(
        bank_code="Techcombank",
        account_number="19038888999900",
        account_name="LE HOANG NAM",
        fandom_id=fandom_id,
    )

    assert res.success is True
    assert res.is_verified is True
    assert res.activation_mode == "sandbox_simulated"
    assert res.sepay_account_id is not None
    assert "Sandbox mô phỏng" in res.activation_note


@pytest.mark.asyncio
async def test_sepay_sandbox_connector_network_error_graceful_fallback():
    """Verifies that network exceptions fall back gracefully without failing the registration."""
    connector = SePaySandboxTokenConnector(api_key="dummy_key")

    with patch("httpx.AsyncClient.get", side_effect=Exception("Connection refused")):
        res = await connector.activate_bank_account(
            bank_code="MBBank",
            account_number="0389123456",
            account_name="TEST USER",
            fandom_id=uuid.uuid4(),
        )

    assert res.success is True
    assert res.is_verified is True
    assert res.activation_mode == "sandbox_offline_fallback"
    assert res.sepay_account_id.startswith("offline_")


@pytest.mark.asyncio
async def test_sepay_oauth_connector_not_implemented_stub():
    """Verifies that OAuth connector stub raises a clear NotImplementedError directing to sandbox mode."""
    connector = SePayOAuthConnector()
    with pytest.raises(NotImplementedError) as exc_info:
        await connector.activate_bank_account(
            bank_code="MBBank",
            account_number="0389123456",
            account_name="TEST USER",
            fandom_id=uuid.uuid4(),
        )
    assert "SEPAY_ACCOUNT_ACTIVATION_MODE='sandbox_token'" in str(exc_info.value)


def test_get_sepay_account_connector_factory():
    """Verifies factory selects the correct connector based on configuration."""
    with patch("app.modules.billing.sepay_connector.settings.SEPAY_ACCOUNT_ACTIVATION_MODE", "sandbox_token"):
        connector = get_sepay_account_connector()
        assert isinstance(connector, SePaySandboxTokenConnector)

    with patch("app.modules.billing.sepay_connector.settings.SEPAY_ACCOUNT_ACTIVATION_MODE", "oauth"):
        connector = get_sepay_account_connector()
        assert isinstance(connector, SePayOAuthConnector)
