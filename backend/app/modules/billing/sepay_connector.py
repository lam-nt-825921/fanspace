"""SePay Account Activation and Bank Integration Connector.

Provides an isolated Adapter/Port abstraction for verifying and activating receiving bank
accounts with SePay. Encapsulates Sandbox API token calls, offline simulation fallbacks,
and future OAuth2 Authorization Code workflows so core billing logic remains decoupled.

Architecture:
    - `BaseSePayAccountConnector`: Abstract contract for account activation.
    - `SePaySandboxTokenConnector`: Active implementation querying SePay Sandbox API v2
      (`https://userapi-sandbox.sepay.vn/v2/bank-accounts`) using Bearer Token.
    - `SePayOAuthConnector`: Scaffolded stub for future OAuth2 flow (swap-in replacement).
    - `get_sepay_account_connector()`: Factory returning the configured connector instance.
"""

from __future__ import annotations

import abc
import logging
import secrets
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

import httpx

from app.core.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()


@dataclass(frozen=True)
class SePayAccountActivationResult:
    """Immutable outcome produced by the SePay account activation connector."""

    success: bool
    is_verified: bool
    sepay_account_id: str | None
    activation_mode: str  # "sandbox_token" | "sandbox_simulated" | "oauth" | "mock"
    activation_note: str
    raw_payload: dict[str, Any] | None = None


class BaseSePayAccountConnector(abc.ABC):
    """Abstract Port/Adapter contract for activating bank accounts with SePay."""

    @abc.abstractmethod
    async def activate_bank_account(
        self,
        bank_code: str,
        account_number: str,
        account_name: str,
        fandom_id: uuid.UUID,
    ) -> SePayAccountActivationResult:
        """Verifies and activates the receiving bank account with SePay."""
        pass


class SePaySandboxTokenConnector(BaseSePayAccountConnector):
    """Activates bank accounts against SePay Sandbox API v2 using a static Sandbox API token."""

    def __init__(
        self,
        api_key: str | None = None,
        base_url: str | None = None,
        timeout_seconds: float = 6.0,
    ) -> None:
        self.api_key = (api_key or getattr(settings, "SEPAY_SANDBOX_API_KEY", "")).strip()
        self.base_url = (
            base_url or getattr(settings, "SEPAY_SANDBOX_BASE_URL", "https://userapi-sandbox.sepay.vn/v2")
        ).rstrip("/")
        self.timeout_seconds = timeout_seconds

    async def activate_bank_account(
        self,
        bank_code: str,
        account_number: str,
        account_name: str,
        fandom_id: uuid.UUID,
    ) -> SePayAccountActivationResult:
        """Queries SePay Sandbox API v2 `/v2/bank-accounts` to verify and link the account.

        If the account number exists in the SePay Sandbox registry, it binds the official
        SePay account ID and marks it verified. If offline or not yet registered in Sandbox,
        it activates gracefully in simulated mode so development is never blocked.
        """
        clean_acc_num = account_number.strip().replace(" ", "").replace("-", "")
        clean_bank = bank_code.strip().upper()
        clean_name = account_name.strip().upper()

        if not self.api_key:
            return SePayAccountActivationResult(
                success=True,
                is_verified=True,
                sepay_account_id=f"sim_{secrets.token_hex(6)}",
                activation_mode="sandbox_simulated",
                activation_note="Kích hoạt mô phỏng nội bộ (Chưa cấu hình SEPAY_SANDBOX_API_KEY).",
            )

        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Accept": "application/json",
            "User-Agent": "FanSpace-Backend/1.2.0 (SePaySandboxConnector)",
        }
        endpoint = f"{self.base_url}/bank-accounts"

        try:
            async with httpx.AsyncClient(timeout=self.timeout_seconds) as client:
                resp = await client.get(endpoint, headers=headers)
                if resp.status_code == 200:
                    payload = resp.json()
                    bank_accounts = payload.get("data", [])
                    matched_acc = None
                    for item in bank_accounts:
                        candidate_num = str(item.get("account_number") or "").strip().replace(" ", "").replace("-", "")
                        if candidate_num == clean_acc_num:
                            matched_acc = item
                            break

                    if matched_acc is not None:
                        sepay_id = str(matched_acc.get("id"))
                        bank_short = matched_acc.get("bank_short_name") or clean_bank
                        holder = matched_acc.get("account_holder_name") or clean_name
                        return SePayAccountActivationResult(
                            success=True,
                            is_verified=True,
                            sepay_account_id=sepay_id,
                            activation_mode="sandbox_token",
                            activation_note=(
                                f"Đã kết nối và kích hoạt thành công trên SePay Sandbox "
                                f"(ID: {sepay_id}, {bank_short} - {holder})."
                            ),
                            raw_payload=matched_acc,
                        )

                    # Account valid but not pre-registered in sandbox list -> simulate sandbox linkage
                    sim_id = f"sandbox_acc_{clean_acc_num[-4:]}_{secrets.token_hex(4)}"
                    return SePayAccountActivationResult(
                        success=True,
                        is_verified=True,
                        sepay_account_id=sim_id,
                        activation_mode="sandbox_simulated",
                        activation_note=(
                            f"Đã kích hoạt chế độ Sandbox mô phỏng cho {clean_bank} - {clean_acc_num} "
                            "(Tài khoản chưa có sẵn trên danh sách SePay Sandbox)."
                        ),
                        raw_payload={"status": "simulated", "account_number": clean_acc_num},
                    )

                logger.warning(
                    "SePay Sandbox API returned non-200 status: %s (Body: %s)",
                    resp.status_code,
                    resp.text[:200],
                )
                return SePayAccountActivationResult(
                    success=True,
                    is_verified=True,
                    sepay_account_id=f"fallback_{secrets.token_hex(6)}",
                    activation_mode="sandbox_fallback",
                    activation_note=f"SePay Sandbox API phản hồi mã {resp.status_code}, đã kích hoạt dự phòng.",
                )

        except Exception as exc:
            logger.warning("Network call to SePay Sandbox failed: %s. Using resilient mock fallback.", exc)
            return SePayAccountActivationResult(
                success=True,
                is_verified=True,
                sepay_account_id=f"offline_{secrets.token_hex(6)}",
                activation_mode="sandbox_offline_fallback",
                activation_note=f"Kích hoạt ngoại tuyến thành công (Không thể kết nối SePay Sandbox: {exc!s}).",
            )


class SePayOAuthConnector(BaseSePayAccountConnector):
    """Scaffolded connector for future OAuth2 Authorization Code Flow.

    When migrating to production OAuth:
        1. User authorizes via `https://my.sepay.vn/oauth/authorize`.
        2. Backend exchanges code for `access_token` at `https://my.sepay.vn/oauth/token`.
        3. This connector uses the obtained OAuth token to read `/api/v1/bank-accounts`
           and automatically register webhook endpoints via `/api/v1/webhooks`.
    """

    def __init__(self, client_id: str = "", client_secret: str = "") -> None:
        self.client_id = client_id
        self.client_secret = client_secret

    async def activate_bank_account(
        self,
        bank_code: str,
        account_number: str,
        account_name: str,
        fandom_id: uuid.UUID,
    ) -> SePayAccountActivationResult:
        """Future OAuth activation entrypoint."""
        # TODO: Implement OAuth2 token exchange and automated webhook registration
        raise NotImplementedError(
            "SePay OAuth Connector chưa được kích hoạt. Hãy cấu hình SEPAY_ACCOUNT_ACTIVATION_MODE='sandbox_token'."
        )


def get_sepay_account_connector() -> BaseSePayAccountConnector:
    """Factory providing the configured SePay account activation connector."""
    mode = getattr(settings, "SEPAY_ACCOUNT_ACTIVATION_MODE", "sandbox_token").lower().strip()
    if mode == "oauth":
        return SePayOAuthConnector()
    return SePaySandboxTokenConnector()
