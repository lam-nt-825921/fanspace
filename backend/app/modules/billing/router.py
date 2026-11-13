"""FastAPI Router for Fandom Monetization, Membership Tiers, Payment Orders, and SePay Webhook."""

import uuid
from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from pydantic import ValidationError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.modules.billing.schemas import (
    FandomBankAccountOut,
    FandomBankAccountUpsert,
    FandomLeaderboardOut,
    FandomLedgerResponse,
    FandomMembershipsListOut,
    ManualTransactionResolveRequest,
    MembershipTierCreate,
    MembershipTierOut,
    MembershipTierUpdate,
    PaymentOrderCreate,
    PaymentOrderOut,
    PaymentTransactionOut,
    SepaySimulateRequest,
    SepayWebhookPayload,
    SepayWebhookResponse,
)
from app.modules.billing.service import BillingService
from app.modules.fandom.emoji_service import FandomEmojiListOut, FandomEmojiService
from app.modules.identity.models import User
from app.modules.identity.service import get_current_user, get_optional_current_user

billing_router = APIRouter(prefix="/api/v1", tags=["Billing & Monetization"])


# ---------------------------------------------------------------------------
# 1. Fandom Bank Account Endpoints
# ---------------------------------------------------------------------------


@billing_router.get(
    "/fandoms/{identifier}/bank-account",
    response_model=FandomBankAccountOut | None,
    summary="Lấy thông tin tài khoản ngân hàng nhận thanh toán của Fandom",
)
async def get_fandom_bank_account(
    identifier: str,
    db: AsyncSession = Depends(get_db),
):
    """Returns the receiving bank account configured for a fandom."""
    return await BillingService.get_bank_account(db=db, identifier=identifier)


@billing_router.put(
    "/fandoms/{identifier}/bank-account",
    response_model=FandomBankAccountOut,
    summary="Thiết lập / Cập nhật tài khoản ngân hàng nhận tiền SePay (Chủ Fandom)",
)
async def upsert_fandom_bank_account(
    identifier: str,
    data: FandomBankAccountUpsert,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Configures the receiving bank account for a fandom."""
    return await BillingService.upsert_bank_account(
        db=db,
        identifier=identifier,
        current_user=current_user,
        data=data,
    )


# ---------------------------------------------------------------------------
# 2. Product Endpoints (Membership Tiers)
# ---------------------------------------------------------------------------


@billing_router.get(
    "/fandoms/{identifier}/memberships",
    response_model=FandomMembershipsListOut,
    summary="Lấy danh sách các gói Hội viên (Membership Tiers) của Fandom",
)
async def list_fandom_memberships(
    identifier: str,
    current_user: User | None = Depends(get_optional_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Lists all paid Membership Tier Roles for a fandom and caller's ownership status."""
    return await BillingService.list_membership_tiers(
        db=db,
        identifier=identifier,
        current_user=current_user,
    )


@billing_router.post(
    "/fandoms/{identifier}/memberships",
    response_model=MembershipTierOut,
    status_code=status.HTTP_201_CREATED,
    summary="Tạo gói Hội viên trả phí mới (Chủ Fandom - Tối đa 4 gói)",
)
async def create_fandom_membership_tier(
    identifier: str,
    data: MembershipTierCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Creates a new paid Membership Tier Role."""
    return await BillingService.create_membership_tier(
        db=db,
        identifier=identifier,
        current_user=current_user,
        data=data,
    )


@billing_router.put(
    "/fandoms/{identifier}/memberships/{role_id}",
    response_model=MembershipTierOut,
    summary="Cập nhật thông tin và giá gói Hội viên (Chủ Fandom)",
)
async def update_fandom_membership_tier(
    identifier: str,
    role_id: uuid.UUID,
    data: MembershipTierUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Updates an existing paid Membership Tier Role."""
    return await BillingService.update_membership_tier(
        db=db,
        identifier=identifier,
        role_id=role_id,
        current_user=current_user,
        data=data,
    )


@billing_router.delete(
    "/fandoms/{identifier}/memberships/{role_id}",
    summary="Xóa gói Hội viên (Chủ Fandom)",
)
async def delete_fandom_membership_tier(
    identifier: str,
    role_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Deletes a paid Membership Tier Role."""
    return await BillingService.delete_membership_tier(
        db=db,
        identifier=identifier,
        role_id=role_id,
        current_user=current_user,
    )


# ---------------------------------------------------------------------------
# 3. Order Endpoints (Yêu cầu mua gói Hội viên)
# ---------------------------------------------------------------------------


@billing_router.post(
    "/fandoms/{identifier}/orders",
    response_model=PaymentOrderOut,
    status_code=status.HTTP_201_CREATED,
    summary="Tạo đơn hàng (Order) mua gói Hội viên kèm mã VietQR SePay",
)
async def create_payment_order(
    identifier: str,
    data: PaymentOrderCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Creates a new PaymentOrder with default SePay payment code (`DH...`) and VietQR URL."""
    return await BillingService.create_order(
        db=db,
        identifier=identifier,
        current_user=current_user,
        data=data,
    )


@billing_router.get(
    "/orders/{order_code}",
    response_model=PaymentOrderOut,
    summary="Kiểm tra trạng thái đơn hàng và các vết giao dịch",
)
async def get_payment_order(
    order_code: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Retrieves an order by `order_code` (`DH...`)."""
    return await BillingService.get_order(
        db=db,
        order_code=order_code,
        current_user=current_user,
    )


@billing_router.post(
    "/orders/{order_code}/cancel",
    response_model=PaymentOrderOut,
    summary="Hủy đơn hàng đang chờ thanh toán",
)
async def cancel_payment_order(
    order_code: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Cancels a PENDING payment order."""
    return await BillingService.cancel_order(
        db=db,
        order_code=order_code,
        current_user=current_user,
    )


# ---------------------------------------------------------------------------
# 4. SePay Webhook & Simulation (Transaction & 3-Way Reconciliation)
# ---------------------------------------------------------------------------


@billing_router.post(
    "/billing/sepay-webhook",
    response_model=SepayWebhookResponse,
    status_code=status.HTTP_200_OK,
    summary="Webhook tiếp nhận biến động số dư từ SePay (Xác thực HMAC-SHA256)",
)
async def receive_sepay_webhook(
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    """Verifies SePay HMAC-SHA256 signature and runs 3-Way Matching in an ACID transaction."""
    raw_body = await request.body()
    BillingService.verify_sepay_webhook_signature(
        raw_body=raw_body,
        headers=request.headers,
    )

    try:
        payload = SepayWebhookPayload.model_validate_json(raw_body)
    except ValidationError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Payload Webhook SePay không hợp lệ: {exc.errors()}",
        ) from exc

    return await BillingService.process_sepay_webhook(db=db, payload=payload)


@billing_router.post(
    "/billing/sepay-simulate",
    response_model=SepayWebhookResponse,
    status_code=status.HTTP_200_OK,
    summary="Giả lập bắn Webhook SePay (Ký HMAC-SHA256 chuẩn) phục vụ Test & Demo",
)
async def simulate_sepay_webhook(
    data: SepaySimulateRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Simulates an incoming SePay webhook call for testing order reconciliation locally."""
    return await BillingService.simulate_sepay_webhook(db=db, data=data)


# ---------------------------------------------------------------------------
# 5. Audit Trail Ledger & Manual Reconciliation (Chủ Fandom)
# ---------------------------------------------------------------------------


@billing_router.get(
    "/fandoms/{identifier}/transactions",
    response_model=FandomLedgerResponse,
    summary="Xem Sổ cái kiểm toán giao dịch (Audit Trail) và Đơn hàng của Fandom",
)
async def get_fandom_ledger(
    identifier: str,
    status_filter: str | None = Query(
        default=None,
        description="Lọc theo trạng thái đối soát: ALL, MATCHED, UNDERPAID, OVERPAID, UNMATCHED_ORDER, EXPIRED_ORDER, MANUAL_MATCHED",
    ),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Retrieves the financial Audit Trail and Orders ledger for the Fandom Owner."""
    return await BillingService.get_fandom_ledger(
        db=db,
        identifier=identifier,
        current_user=current_user,
        status_filter=status_filter,
    )


@billing_router.post(
    "/fandoms/{identifier}/transactions/{transaction_id}/resolve",
    response_model=PaymentTransactionOut,
    summary="Chủ Fandom duyệt đối soát thủ công giao dịch bị lệch vào một đơn hàng",
)
async def resolve_transaction_manually(
    identifier: str,
    transaction_id: uuid.UUID,
    data: ManualTransactionResolveRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Manually reconciles a discrepant transaction to a target order and provisions the role."""
    return await BillingService.resolve_transaction_manually(
        db=db,
        identifier=identifier,
        transaction_id=transaction_id,
        current_user=current_user,
        data=data,
    )


# ---------------------------------------------------------------------------
# 6. Dual-Tab Membership Leaderboard (Spending & Streak)
# ---------------------------------------------------------------------------


@billing_router.get(
    "/fandoms/{identifier}/leaderboard",
    response_model=FandomLeaderboardOut,
    summary="Bảng xếp hạng Hội viên Fandom (2 Tabs: Theo tổng tiền ủng hộ & Theo chuỗi gia hạn)",
)
async def get_fandom_leaderboard(
    identifier: str,
    limit: int = Query(default=50, ge=1, le=100),
    current_user: User | None = Depends(get_optional_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Returns the dual-tab Fandom Membership Leaderboard (Top Spending & Top Streak)."""
    return await BillingService.get_fandom_leaderboard(
        db=db,
        identifier=identifier,
        current_user=current_user,
        limit=limit,
    )


# ---------------------------------------------------------------------------
# 7. Fandom Exclusive Emojis & Stickers
# ---------------------------------------------------------------------------


@billing_router.get(
    "/fandoms/{identifier}/emojis",
    response_model=FandomEmojiListOut,
    summary="Lấy danh sách bộ Emoji & Sticker độc quyền của Fandom kèm trạng thái mở khóa theo gói Hội viên",
)
async def list_fandom_emojis(
    identifier: str,
    current_user: User | None = Depends(get_optional_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Lists all custom Emojis and Stickers in a Fandom and whether the caller has unlocked each item."""
    return await FandomEmojiService.list_fandom_emojis(
        db=db,
        identifier=identifier,
        current_user=current_user,
    )


