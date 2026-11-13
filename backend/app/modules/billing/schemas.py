"""Pydantic schemas for Fandom Monetization, Membership Tiers, and SePay 3-Way Reconciliation."""

import uuid
from datetime import datetime
from pydantic import BaseModel, Field


class FandomBankAccountUpsert(BaseModel):
    """Payload for configuring a fandom's receiving bank account on SePay."""

    bank_code: str = Field(
        ...,
        min_length=2,
        max_length=50,
        description="Mã ngân hàng theo chuẩn SePay/VietQR (VD: MBBank, Vietcombank, Techcombank, ACB, BIDV)",
    )
    account_number: str = Field(
        ...,
        min_length=4,
        max_length=50,
        description="Số tài khoản ngân hàng nhận tiền (hoặc số tài khoản ảo VA)",
    )
    account_name: str = Field(
        ...,
        min_length=2,
        max_length=100,
        description="Tên chủ tài khoản in hoa không dấu (VD: NGUYEN VAN A)",
    )
    is_active: bool = Field(default=True, description="Trạng thái kích hoạt nhận thanh toán")


class FandomBankAccountOut(BaseModel):
    """Public/Owner representation of a fandom's receiving bank account."""

    id: uuid.UUID
    fandom_id: uuid.UUID
    bank_code: str
    account_number: str
    account_name: str
    is_active: bool
    updated_at: datetime

    model_config = {"from_attributes": True}


class MembershipTierCreate(BaseModel):
    """Payload for creating a paid Membership Tier Role (Product)."""

    name: str = Field(..., min_length=1, max_length=50, description="Tên gói Hội viên (VD: Fan Cứng VIP)")
    tier_level: int = Field(default=1, ge=1, le=4, description="Cấp bậc gói hội viên từ 1 đến 4")
    color_hex: str = Field(
        default="#FFD700",
        pattern=r"^#[0-9a-fA-F]{6}$",
        description="Mã màu tên vinh danh trên khung chat",
    )
    priority: int = Field(default=50, ge=1, le=900, description="Thứ bậc ưu tiên hiển thị vai trò")
    permissions_bitmask: int = Field(default=0, ge=0, description="Bitmask quyền hạn đặc biệt đi kèm gói")
    membership_perks_bitmask: int = Field(
        default=15,
        ge=0,
        description="Bitmask đặc quyền Hội viên tách biệt (Emoji, Sticker, Huy hiệu VIP, Kênh ưu tiên)",
    )
    price_fiat_vnd: int = Field(
        ...,
        ge=2000,
        le=100_000_000,
        description="Đơn giá bán gói hội viên bằng VNĐ (tối thiểu 2.000đ)",
    )
    duration_days: int = Field(
        default=30,
        ge=1,
        le=3650,
        description="Thời hạn hiệu lực của gói tính theo ngày (VD: 30, 90, 365)",
    )
    icon_url: str | None = Field(default=None, description="Icon hoặc mô tả ngắn quyền lợi gói")


class MembershipTierUpdate(BaseModel):
    """Payload for updating an existing Membership Tier Role."""

    name: str | None = Field(default=None, min_length=1, max_length=50)
    tier_level: int | None = Field(default=None, ge=1, le=4)
    color_hex: str | None = Field(default=None, pattern=r"^#[0-9a-fA-F]{6}$")
    priority: int | None = Field(default=None, ge=1, le=900)
    permissions_bitmask: int | None = Field(default=None, ge=0)
    membership_perks_bitmask: int | None = Field(default=None, ge=0)
    price_fiat_vnd: int | None = Field(default=None, ge=2000, le=100_000_000)
    duration_days: int | None = Field(default=None, ge=1, le=3650)
    icon_url: str | None = Field(default=None)


class MembershipTierOut(BaseModel):
    """Representation of a Membership Tier Product along with caller ownership state."""

    id: uuid.UUID
    fandom_id: uuid.UUID
    name: str
    tier_level: int
    color_hex: str
    priority: int
    permissions_bitmask: int
    membership_perks_bitmask: int = 15
    price_fiat_vnd: int
    duration_days: int
    icon_url: str | None = None
    is_owned: bool = False
    owned_expires_at: datetime | None = None
    created_at: datetime


class FandomMembershipsListOut(BaseModel):
    """Aggregated response of a fandom's bank configuration and available Membership Tiers."""

    fandom_id: uuid.UUID
    bank_configured: bool
    bank_account: FandomBankAccountOut | None = None
    tiers: list[MembershipTierOut] = Field(default_factory=list)


class PaymentOrderCreate(BaseModel):
    """Payload for creating a new payment order for a Membership Tier."""

    role_id: uuid.UUID = Field(..., description="ID của gói Membership Tier cần mua")


class PaymentTransactionOut(BaseModel):
    """Audit Trail record of a bank transaction processed from SePay."""

    id: uuid.UUID
    sepay_transaction_id: int
    order_id: uuid.UUID | None = None
    order_code: str | None = None
    user_id: uuid.UUID | None = None
    fandom_id: uuid.UUID | None = None
    gateway: str
    transaction_date: str
    account_number: str
    transfer_type: str
    transfer_amount: int
    code: str | None = None
    content: str
    reference_code: str | None = None
    reconciliation_status: str
    audit_note: str | None = None
    created_at: datetime

    model_config = {"from_attributes": True}


class PaymentOrderOut(BaseModel):
    """Detailed representation of a PaymentOrder and its reconciliation state."""

    id: uuid.UUID
    order_code: str
    user_id: uuid.UUID
    fandom_id: uuid.UUID
    role_id: uuid.UUID
    role_name: str
    amount_vnd: int
    paid_amount_vnd: int
    remaining_amount_vnd: int
    duration_days: int
    bank_code: str
    account_number: str
    account_name: str
    qr_url: str
    status: str
    expires_at: datetime
    paid_at: datetime | None = None
    member_role_expires_at: datetime | None = None
    created_at: datetime
    transactions: list[PaymentTransactionOut] = Field(default_factory=list)


class SepayWebhookPayload(BaseModel):
    """Standard incoming JSON payload sent by SePay Webhook."""

    id: int = Field(..., description="ID giao dịch duy nhất trên hệ thống SePay")
    gateway: str = Field(default="MBBank", description="Tên ngân hàng nhận tiền")
    transactionDate: str = Field(default="", description="Thời gian giao dịch phía ngân hàng")
    accountNumber: str = Field(default="", description="Số tài khoản ngân hàng nhận")
    subAccount: str | None = Field(default=None, description="Tài khoản ảo VA (nếu có)")
    code: str | None = Field(
        default=None,
        description="Mã thanh toán mặc định (VD: DH12345678) do SePay tự động bóc tách",
    )
    content: str = Field(default="", description="Nội dung chuyển khoản gốc")
    transferType: str = Field(default="in", description="Loại giao dịch: 'in' hoặc 'out'")
    description: str | None = Field(default=None, description="Chi tiết nội dung thông báo ngân hàng")
    transferAmount: int = Field(..., ge=0, description="Số tiền giao dịch (VNĐ)")
    accumulated: int | None = Field(default=None, description="Số dư lũy kế")
    referenceCode: str | None = Field(default=None, description="Mã tham chiếu ngân hàng (FT code)")


class SepayWebhookResponse(BaseModel):
    """Response returned to SePay upon webhook processing."""

    success: bool = True
    idempotent_replay: bool = False
    reconciliation_status: str
    order_code: str | None = None
    order_status: str | None = None
    message: str


class SepaySimulateRequest(BaseModel):
    """Payload for simulating a SePay webhook call in local/sandbox environments."""

    order_code: str = Field(..., description="Mã đơn hàng cần giả lập thanh toán (VD: DH12345678)")
    transfer_amount: int | None = Field(
        default=None,
        gt=0,
        description="Số tiền chuyển khoản giả lập (nếu để trống sẽ lấy đúng số tiền còn thiếu của đơn)",
    )
    custom_content: str | None = Field(
        default=None,
        description="Nội dung chuyển khoản tùy chỉnh (dùng để test kịch bản ghi sai mã đơn hàng)",
    )
    gateway: str = Field(default="MBBank", description="Ngân hàng giả lập")


class ManualTransactionResolveRequest(BaseModel):
    """Payload for Fandom Owner to manually reconcile an unmatched/discrepant transaction."""

    order_code: str = Field(..., description="Mã đơn hàng (DH...) cần gắn với giao dịch này")
    note: str | None = Field(default=None, description="Ghi chú đối soát thủ công của Chủ Fandom")


class FandomLedgerResponse(BaseModel):
    """Aggregated ledger view for Fandom Owner containing both Orders and Audit Trail Transactions."""

    fandom_id: uuid.UUID
    total_revenue_vnd: int = 0
    paid_orders_count: int = 0
    discrepant_transactions_count: int = 0
    orders: list[PaymentOrderOut] = Field(default_factory=list)
    transactions: list[PaymentTransactionOut] = Field(default_factory=list)


class LeaderboardSpendingEntryOut(BaseModel):
    """Single ranked entry in the Fandom Spending Leaderboard tab."""

    rank: int
    user_id: uuid.UUID
    username: str
    display_name: str
    avatar_url: str | None = None
    total_spent_vnd: int
    paid_orders_count: int
    highest_tier_name: str | None = None
    highest_tier_level: int | None = None
    highest_tier_color_hex: str | None = None


class LeaderboardStreakEntryOut(BaseModel):
    """Single ranked entry in the Fandom Membership Renewal Streak Leaderboard tab."""

    rank: int
    user_id: uuid.UUID
    username: str
    display_name: str
    avatar_url: str | None = None
    streak_count: int
    streak_days: int
    tier_name: str
    tier_level: int
    tier_color_hex: str
    streak_started_at: datetime | None = None
    expires_at: datetime | None = None
    is_active: bool = True


class FandomLeaderboardOut(BaseModel):
    """Dual-tab Fandom Leaderboard response (Spending & Membership Streak)."""

    fandom_id: uuid.UUID
    spending_leaderboard: list[LeaderboardSpendingEntryOut] = Field(default_factory=list)
    streak_leaderboard: list[LeaderboardStreakEntryOut] = Field(default_factory=list)
    my_spending_entry: LeaderboardSpendingEntryOut | None = None
    my_streak_entry: LeaderboardStreakEntryOut | None = None
