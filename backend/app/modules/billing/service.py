"""Billing Service handling DB retrieval, validation, and ACID transaction orchestration.

All pure domain calculations, SePay HMAC-SHA256 verification, VietQR URL generation,
and 3-Way Matching evaluation are delegated to `app.modules.billing.reconciliation`.
"""

from __future__ import annotations

import secrets
import uuid
from datetime import datetime, timedelta, timezone

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.modules.billing.models import FandomBankAccount, PaymentOrder, PaymentTransaction
from app.modules.billing.reconciliation import (
    MAX_MEMBERSHIP_TIERS_PER_FANDOM,
    build_fandom_leaderboard_response,
    build_fandom_ledger_response,
    build_sepay_qr_url,
    build_simulated_sepay_payload,
    build_transaction_entity,
    calculate_membership_expiry,
    calculate_membership_streak,
    compute_sepay_hmac_signature,
    compute_tier_permissions_bitmask,
    evaluate_3way_reconciliation,
    extract_sepay_order_code,
    serialize_order_out,
    serialize_tier_out,
    serialize_transaction_out,
    verify_sepay_webhook_signature,
)
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
from app.modules.fandom.models import Fandom, FandomMember
from app.modules.fandom.service import FandomService
from app.modules.identity.models import User
from app.modules.rbac.models import MemberRole, PermissionBit, Role

settings = get_settings()


async def _emit_billing_event(**payload: object) -> None:
    """Broadcasts real-time role/payment updates over Socket.IO without failing the DB flow."""
    try:
        from app.main import sio

        await sio.emit("fandom_roles_updated", payload)
    except Exception:
        pass


class BillingService:
    """Orchestrates data access, validation, and ACID transactions for Fandom Billing."""

    compute_sepay_hmac_signature = staticmethod(compute_sepay_hmac_signature)
    verify_sepay_webhook_signature = staticmethod(verify_sepay_webhook_signature)

    @staticmethod
    async def _require_active_member(
        db: AsyncSession, fandom: Fandom, user_id: uuid.UUID
    ) -> FandomMember | None:
        """Verifies that `user_id` is not BANNED from `fandom`."""
        res = await db.execute(
            select(FandomMember).where(
                FandomMember.fandom_id == fandom.id,
                FandomMember.user_id == user_id,
            )
        )
        member = res.scalar_one_or_none()
        if member is not None and member.status == "BANNED":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Bạn đã bị cấm khỏi Fandom này và không thể mua gói Hội viên.",
            )
        return member

    @staticmethod
    async def _require_fandom_owner_or_admin(
        db: AsyncSession, fandom: Fandom, user: User
    ) -> None:
        """Verifies that `user` is the Fandom Owner or holds ADMINISTRATOR permission."""
        if fandom.owner_id == user.id:
            return
        _, bitmask, is_owner = await FandomService._get_member_priority_and_permissions(
            db, fandom.id, user.id
        )
        if not is_owner and not (bitmask & PermissionBit.ADMINISTRATOR):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Chỉ Chủ sở hữu (Owner) hoặc Quản trị viên Fandom mới có quyền thực hiện thao tác này.",
            )

    @staticmethod
    async def _generate_unique_order_code(db: AsyncSession) -> str:
        """Generates a unique default SePay payment code (`DH` + 8 digits)."""
        prefix = settings.SEPAY_PAYMENT_CODE_PREFIX.upper()
        for _ in range(10):
            code = f"{prefix}{secrets.randbelow(90_000_000) + 10_000_000}"
            exists = await db.execute(
                select(PaymentOrder.id).where(PaymentOrder.order_code == code)
            )
            if exists.scalar_one_or_none() is None:
                return code
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Không thể sinh mã đơn hàng SePay duy nhất.",
        )

    @staticmethod
    async def _provision_membership_role_atomic(
        db: AsyncSession,
        fandom_id: uuid.UUID,
        user_id: uuid.UUID,
        role_id: uuid.UUID,
        duration_days: int,
        now: datetime,
    ) -> datetime:
        """Atomically grants or extends a user's `MemberRole.expires_at` and renewal streak inside the caller's transaction."""
        mem_res = await db.execute(
            select(FandomMember)
            .where(FandomMember.fandom_id == fandom_id, FandomMember.user_id == user_id)
            .with_for_update()
        )
        member = mem_res.scalar_one_or_none()
        if member is None:
            db.add(FandomMember(user_id=user_id, fandom_id=fandom_id, status="ACTIVE"))
            await db.flush()
        elif member.status == "LEFT":
            member.status = "ACTIVE"

        mr_res = await db.execute(
            select(MemberRole)
            .where(
                MemberRole.fandom_id == fandom_id,
                MemberRole.user_id == user_id,
                MemberRole.role_id == role_id,
            )
            .with_for_update()
        )
        member_role = mr_res.scalar_one_or_none()
        streak_update = calculate_membership_streak(
            current_expires_at=member_role.expires_at if member_role else None,
            current_streak_count=member_role.streak_count if member_role else 0,
            current_streak_days=member_role.streak_days if member_role else 0,
            current_streak_started_at=(
                member_role.streak_started_at if member_role else None
            ),
            duration_days=duration_days,
            now=now,
        )
        if member_role is None:
            db.add(
                MemberRole(
                    fandom_id=fandom_id,
                    user_id=user_id,
                    role_id=role_id,
                    expires_at=streak_update.new_expires_at,
                    streak_count=streak_update.streak_count,
                    streak_days=streak_update.streak_days,
                    streak_started_at=streak_update.streak_started_at,
                )
            )
        else:
            member_role.expires_at = streak_update.new_expires_at
            member_role.streak_count = streak_update.streak_count
            member_role.streak_days = streak_update.streak_days
            member_role.streak_started_at = streak_update.streak_started_at
        return streak_update.new_expires_at

    # ------------------------------------------------------------------
    # 1. Fandom Bank Account Configuration
    # ------------------------------------------------------------------

    @staticmethod
    async def get_bank_account(
        db: AsyncSession, identifier: str
    ) -> FandomBankAccountOut | None:
        """Retrieves the configured bank account for a Fandom, or None."""
        fandom = await FandomService._resolve_fandom(db, identifier)
        res = await db.execute(
            select(FandomBankAccount).where(FandomBankAccount.fandom_id == fandom.id)
        )
        acc = res.scalar_one_or_none()
        return FandomBankAccountOut.model_validate(acc) if acc else None

    @staticmethod
    async def upsert_bank_account(
        db: AsyncSession,
        identifier: str,
        current_user: User,
        data: FandomBankAccountUpsert,
    ) -> FandomBankAccountOut:
        """Creates or updates the Fandom's receiving bank account (Owner only)."""
        fandom = await FandomService._resolve_fandom(db, identifier)
        await BillingService._require_fandom_owner_or_admin(db, fandom, current_user)

        res = await db.execute(
            select(FandomBankAccount).where(FandomBankAccount.fandom_id == fandom.id)
        )
        acc = res.scalar_one_or_none()
        if acc is None:
            acc = FandomBankAccount(
                fandom_id=fandom.id,
                bank_code=data.bank_code.strip(),
                account_number=data.account_number.strip(),
                account_name=data.account_name.strip().upper(),
                is_active=data.is_active,
            )
            db.add(acc)
        else:
            acc.bank_code = data.bank_code.strip()
            acc.account_number = data.account_number.strip()
            acc.account_name = data.account_name.strip().upper()
            acc.is_active = data.is_active

        await db.commit()
        await db.refresh(acc)
        return FandomBankAccountOut.model_validate(acc)

    # ------------------------------------------------------------------
    # 2. Product Management: Membership Tiers (Paid Roles, Max 4)
    # ------------------------------------------------------------------

    @staticmethod
    async def list_membership_tiers(
        db: AsyncSession, identifier: str, current_user: User | None = None
    ) -> FandomMembershipsListOut:
        """Lists all paid Membership Tier Roles (`is_membership_tier = True`) for a Fandom."""
        fandom = await FandomService._resolve_fandom(db, identifier)
        bank_res = await db.execute(
            select(FandomBankAccount).where(FandomBankAccount.fandom_id == fandom.id)
        )
        bank_acc = bank_res.scalar_one_or_none()

        tiers_res = await db.execute(
            select(Role)
            .where(Role.fandom_id == fandom.id, Role.is_membership_tier.is_(True))
            .order_by(
                Role.tier_level.asc().nulls_last(),
                Role.price_fiat_vnd.asc().nulls_last(),
            )
        )
        tiers = list(tiers_res.scalars().all())

        owned_expiry: dict[uuid.UUID, datetime | None] = {}
        owned_ids: set[uuid.UUID] = set()
        now = datetime.now(timezone.utc)

        if current_user is not None and tiers:
            mr_res = await db.execute(
                select(MemberRole).where(
                    MemberRole.fandom_id == fandom.id,
                    MemberRole.user_id == current_user.id,
                    MemberRole.role_id.in_([t.id for t in tiers]),
                )
            )
            for mr in mr_res.scalars().all():
                if mr.expires_at is None or mr.expires_at > now:
                    owned_ids.add(mr.role_id)
                    owned_expiry[mr.role_id] = mr.expires_at

        return FandomMembershipsListOut(
            fandom_id=fandom.id,
            bank_configured=bool(bank_acc and bank_acc.is_active),
            bank_account=(
                FandomBankAccountOut.model_validate(bank_acc) if bank_acc else None
            ),
            tiers=[
                serialize_tier_out(t, t.id in owned_ids, owned_expiry.get(t.id))
                for t in tiers
            ],
        )

    @staticmethod
    async def create_membership_tier(
        db: AsyncSession,
        identifier: str,
        current_user: User,
        data: MembershipTierCreate,
    ) -> MembershipTierOut:
        """Creates a new paid Membership Tier Role (`is_membership_tier = True`, max 4 per Fandom)."""
        fandom = await FandomService._resolve_fandom(db, identifier)
        await BillingService._require_fandom_owner_or_admin(db, fandom, current_user)

        count_res = await db.execute(
            select(func.count(Role.id)).where(
                Role.fandom_id == fandom.id, Role.is_membership_tier.is_(True)
            )
        )
        current_count = int(count_res.scalar() or 0)
        if current_count >= MAX_MEMBERSHIP_TIERS_PER_FANDOM:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Mỗi Fandom chỉ được phép tạo tối đa {MAX_MEMBERSHIP_TIERS_PER_FANDOM} gói Hội viên trả phí.",
            )

        dup_res = await db.execute(
            select(Role.id).where(
                Role.fandom_id == fandom.id,
                func.lower(Role.name) == data.name.strip().lower(),
            )
        )
        if dup_res.scalar_one_or_none() is not None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"Tên gói/vai trò '{data.name.strip()}' đã tồn tại trong Fandom.",
            )

        tier_role = Role(
            fandom_id=fandom.id,
            name=data.name.strip(),
            color_hex=data.color_hex,
            icon_url=data.icon_url,
            priority=data.priority,
            permissions_bitmask=compute_tier_permissions_bitmask(
                data.permissions_bitmask
            ),
            membership_perks_bitmask=int(data.membership_perks_bitmask),
            is_preset_mod=False,
            is_membership_tier=True,
            tier_level=data.tier_level or (current_count + 1),
            price_fiat_vnd=data.price_fiat_vnd,
            duration_days=data.duration_days,
        )
        db.add(tier_role)
        await db.commit()
        await db.refresh(tier_role)
        await _emit_billing_event(fandom_id=str(fandom.id), action="tier_created")
        return serialize_tier_out(tier_role)

    @staticmethod
    async def update_membership_tier(
        db: AsyncSession,
        identifier: str,
        role_id: uuid.UUID,
        current_user: User,
        data: MembershipTierUpdate,
    ) -> MembershipTierOut:
        """Updates an existing paid Membership Tier Role."""
        fandom = await FandomService._resolve_fandom(db, identifier)
        await BillingService._require_fandom_owner_or_admin(db, fandom, current_user)

        res = await db.execute(
            select(Role).where(
                Role.id == role_id,
                Role.fandom_id == fandom.id,
                Role.is_membership_tier.is_(True),
            )
        )
        tier_role = res.scalar_one_or_none()
        if tier_role is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Không tìm thấy gói Hội viên trong Fandom này.",
            )

        for field, value in data.model_dump(exclude_unset=True).items():
            if value is not None:
                setattr(
                    tier_role,
                    field,
                    value.strip() if isinstance(value, str) and field == "name" else value,
                )

        await db.commit()
        await db.refresh(tier_role)
        await _emit_billing_event(fandom_id=str(fandom.id), action="tier_updated")
        return serialize_tier_out(tier_role)

    @staticmethod
    async def delete_membership_tier(
        db: AsyncSession,
        identifier: str,
        role_id: uuid.UUID,
        current_user: User,
    ) -> dict[str, str]:
        """Deletes a paid Membership Tier Role."""
        fandom = await FandomService._resolve_fandom(db, identifier)
        await BillingService._require_fandom_owner_or_admin(db, fandom, current_user)

        res = await db.execute(
            select(Role).where(
                Role.id == role_id,
                Role.fandom_id == fandom.id,
                Role.is_membership_tier.is_(True),
            )
        )
        tier_role = res.scalar_one_or_none()
        if tier_role is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Không tìm thấy gói Hội viên để xóa.",
            )

        await db.delete(tier_role)
        await db.commit()
        await _emit_billing_event(fandom_id=str(fandom.id), action="tier_deleted")
        return {"message": f"Đã xóa gói Hội viên '{tier_role.name}' thành công."}

    # ------------------------------------------------------------------
    # 3. Order Creation & Lifecycle
    # ------------------------------------------------------------------

    @staticmethod
    async def create_order(
        db: AsyncSession,
        identifier: str,
        current_user: User,
        data: PaymentOrderCreate,
    ) -> PaymentOrderOut:
        """Creates a new `PaymentOrder` with frozen product pricing and a SePay VietQR URL."""
        fandom = await FandomService._resolve_fandom(db, identifier)
        await BillingService._require_active_member(db, fandom, current_user.id)

        role_res = await db.execute(
            select(Role).where(
                Role.id == data.role_id,
                Role.fandom_id == fandom.id,
                Role.is_membership_tier.is_(True),
            )
        )
        tier_role = role_res.scalar_one_or_none()
        if tier_role is None or not tier_role.price_fiat_vnd:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Gói Hội viên không tồn tại hoặc chưa thiết lập giá bán.",
            )

        bank_res = await db.execute(
            select(FandomBankAccount).where(
                FandomBankAccount.fandom_id == fandom.id,
                FandomBankAccount.is_active.is_(True),
            )
        )
        bank_acc = bank_res.scalar_one_or_none()
        if bank_acc is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Chủ Fandom chưa thiết lập tài khoản ngân hàng nhận thanh toán SePay.",
            )

        order_code = await BillingService._generate_unique_order_code(db)
        now = datetime.now(timezone.utc)
        amount_vnd = int(tier_role.price_fiat_vnd)

        order = PaymentOrder(
            order_code=order_code,
            user_id=current_user.id,
            fandom_id=fandom.id,
            role_id=tier_role.id,
            role_name_snapshot=tier_role.name,
            amount_vnd=amount_vnd,
            paid_amount_vnd=0,
            duration_days=int(tier_role.duration_days or 30),
            bank_code=bank_acc.bank_code,
            account_number=bank_acc.account_number,
            account_name=bank_acc.account_name,
            qr_url=build_sepay_qr_url(
                bank_acc.bank_code, bank_acc.account_number, amount_vnd, order_code
            ),
            status="PENDING",
            expires_at=now + timedelta(minutes=settings.SEPAY_ORDER_TTL_MINUTES),
        )
        db.add(order)
        await db.commit()
        await db.refresh(order)
        return serialize_order_out(order, transactions=[])

    @staticmethod
    async def get_order(
        db: AsyncSession, order_code: str, current_user: User
    ) -> PaymentOrderOut:
        """Retrieves an order by `order_code`, lazily marking expired PENDING orders."""
        res = await db.execute(
            select(PaymentOrder).where(
                PaymentOrder.order_code == order_code.strip().upper()
            )
        )
        order = res.scalar_one_or_none()
        if order is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Không tìm thấy đơn hàng.",
            )

        fandom = await FandomService._resolve_fandom(db, str(order.fandom_id))
        if order.user_id != current_user.id:
            await BillingService._require_fandom_owner_or_admin(
                db, fandom, current_user
            )

        if order.status == "PENDING" and datetime.now(timezone.utc) > order.expires_at:
            order.status = "EXPIRED"
            await db.commit()
            await db.refresh(order)

        tx_res = await db.execute(
            select(PaymentTransaction)
            .where(PaymentTransaction.order_id == order.id)
            .order_by(PaymentTransaction.created_at.asc())
        )
        txs = list(tx_res.scalars().all())

        member_role_expires_at: datetime | None = None
        if order.role_id is not None and order.status in ("PAID", "OVERPAID"):
            mr_res = await db.execute(
                select(MemberRole.expires_at).where(
                    MemberRole.fandom_id == order.fandom_id,
                    MemberRole.user_id == order.user_id,
                    MemberRole.role_id == order.role_id,
                )
            )
            member_role_expires_at = mr_res.scalar_one_or_none()

        return serialize_order_out(order, txs, member_role_expires_at)

    @staticmethod
    async def cancel_order(
        db: AsyncSession, order_code: str, current_user: User
    ) -> PaymentOrderOut:
        """Cancels a PENDING order belonging to `current_user`."""
        res = await db.execute(
            select(PaymentOrder).where(
                PaymentOrder.order_code == order_code.strip().upper()
            )
        )
        order = res.scalar_one_or_none()
        if order is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Không tìm thấy đơn hàng.",
            )
        if order.user_id != current_user.id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Bạn không có quyền hủy đơn hàng của người khác.",
            )
        if order.status != "PENDING":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Không thể hủy đơn hàng đang ở trạng thái {order.status}.",
            )

        order.status = "CANCELLED"
        await db.commit()
        await db.refresh(order)
        return serialize_order_out(order, transactions=[])

    # ------------------------------------------------------------------
    # 4. SePay Webhook ACID Orchestration & 3-Way Matching
    # ------------------------------------------------------------------

    @staticmethod
    async def process_sepay_webhook(
        db: AsyncSession, payload: SepayWebhookPayload
    ) -> SepayWebhookResponse:
        """Processes an incoming SePay webhook inside an atomic PostgreSQL ACID transaction."""
        existing_res = await db.execute(
            select(PaymentTransaction).where(
                PaymentTransaction.sepay_transaction_id == payload.id
            )
        )
        existing_tx = existing_res.scalar_one_or_none()
        if existing_tx is not None:
            return SepayWebhookResponse(
                success=True,
                idempotent_replay=True,
                reconciliation_status=existing_tx.reconciliation_status,
                order_code=existing_tx.code,
                order_status=None,
                transaction_id=existing_tx.id,
                message=f"Giao dịch SePay #{payload.id} đã được xử lý trước đó (Idempotency Replay).",
            )

        extracted_code = extract_sepay_order_code(payload)
        now = datetime.now(timezone.utc)

        if (payload.transferType or "").lower() != "in":
            tx = build_transaction_entity(
                payload=payload,
                reconciliation_status="IGNORED_OUTGOING",
                audit_note="Giao dịch tiền ra (transferType=out), chỉ lưu vết kiểm toán.",
                code=extracted_code,
            )
            db.add(tx)
            await db.commit()
            await db.refresh(tx)
            return SepayWebhookResponse(
                success=True,
                idempotent_replay=False,
                reconciliation_status=tx.reconciliation_status,
                order_code=extracted_code,
                order_status=None,
                transaction_id=tx.id,
                message=tx.audit_note or "",
            )

        order: PaymentOrder | None = None
        if extracted_code:
            order_res = await db.execute(
                select(PaymentOrder)
                .where(PaymentOrder.order_code == extracted_code)
                .with_for_update()
            )
            order = order_res.scalar_one_or_none()

        if order is None:
            orphan_fandom_id: uuid.UUID | None = None
            if payload.accountNumber:
                acc_res = await db.execute(
                    select(FandomBankAccount.fandom_id).where(
                        FandomBankAccount.account_number == payload.accountNumber.strip()
                    )
                )
                orphan_fandom_id = acc_res.scalar_one_or_none()

            tx = build_transaction_entity(
                payload=payload,
                reconciliation_status="UNMATCHED_ORDER",
                audit_note=(
                    f"Không tìm thấy đơn hàng khớp mã '{extracted_code or 'TRỐNG'}'. "
                    "Đã lưu vết giao dịch mồ côi chờ Chủ Fandom đối soát thủ công."
                ),
                code=extracted_code,
                fandom_id=orphan_fandom_id,
            )
            db.add(tx)
            await db.commit()
            await db.refresh(tx)
            return SepayWebhookResponse(
                success=True,
                idempotent_replay=False,
                reconciliation_status=tx.reconciliation_status,
                order_code=extracted_code,
                order_status=None,
                transaction_id=tx.id,
                message=tx.audit_note or "",
            )

        decision = evaluate_3way_reconciliation(order, payload.transferAmount, now)
        order.status = decision.new_order_status
        order.paid_amount_vnd = decision.new_paid_amount_vnd
        if decision.mark_paid_timestamp:
            order.paid_at = now

        provisioned_until: datetime | None = None
        if decision.should_provision_role and order.role_id is not None:
            provisioned_until = await BillingService._provision_membership_role_atomic(
                db, order.fandom_id, order.user_id, order.role_id, order.duration_days, now
            )

        audit_note = decision.audit_note
        if provisioned_until is not None:
            audit_note = f"{audit_note} Hạn hội viên đến {provisioned_until.strftime('%d/%m/%Y %H:%M UTC')}."

        tx = build_transaction_entity(
            payload=payload,
            reconciliation_status=decision.reconciliation_status,
            audit_note=audit_note,
            code=order.order_code,
            order_id=order.id,
            user_id=order.user_id,
            fandom_id=order.fandom_id,
        )
        db.add(tx)
        await db.commit()
        await db.refresh(tx)

        if decision.should_provision_role:
            await _emit_billing_event(
                fandom_id=str(order.fandom_id),
                action="membership_activated",
                target_user_id=str(order.user_id),
                order_code=order.order_code,
                order_status=order.status,
                reconciliation_status=decision.reconciliation_status,
            )

        return SepayWebhookResponse(
            success=True,
            idempotent_replay=False,
            reconciliation_status=tx.reconciliation_status,
            order_code=order.order_code,
            order_status=order.status,
            transaction_id=tx.id,
            message=audit_note,
        )

    @staticmethod
    async def simulate_sepay_webhook(
        db: AsyncSession, data: SepaySimulateRequest
    ) -> SepayWebhookResponse:
        """Simulates a signed SePay webhook notification for local testing and sandbox demos."""
        res = await db.execute(
            select(PaymentOrder).where(
                PaymentOrder.order_code == data.order_code.strip().upper()
            )
        )
        order = res.scalar_one_or_none()
        payload = build_simulated_sepay_payload(data, order)
        return await BillingService.process_sepay_webhook(db=db, payload=payload)

    # ------------------------------------------------------------------
    # 5. Audit Trail Ledger & Manual Reconciliation
    # ------------------------------------------------------------------

    @staticmethod
    async def get_fandom_ledger(
        db: AsyncSession,
        identifier: str,
        current_user: User,
        status_filter: str | None = None,
    ) -> FandomLedgerResponse:
        """Returns the financial Audit Trail (Transactions + Orders) for the Fandom Owner."""
        fandom = await FandomService._resolve_fandom(db, identifier)
        await BillingService._require_fandom_owner_or_admin(db, fandom, current_user)

        tx_stmt = (
            select(PaymentTransaction)
            .where(PaymentTransaction.fandom_id == fandom.id)
            .order_by(PaymentTransaction.created_at.desc())
        )
        if status_filter and status_filter.upper() != "ALL":
            tx_stmt = tx_stmt.where(
                PaymentTransaction.reconciliation_status == status_filter.upper()
            )
        tx_res = await db.execute(tx_stmt.limit(100))
        transactions = list(tx_res.scalars().all())

        orders_res = await db.execute(
            select(PaymentOrder)
            .where(PaymentOrder.fandom_id == fandom.id)
            .order_by(PaymentOrder.created_at.desc())
            .limit(100)
        )
        orders = list(orders_res.scalars().all())

        rev_res = await db.execute(
            select(func.coalesce(func.sum(PaymentTransaction.transfer_amount), 0)).where(
                PaymentTransaction.fandom_id == fandom.id,
                PaymentTransaction.transfer_type == "in",
                PaymentTransaction.reconciliation_status.in_(
                    ("MATCHED", "OVERPAID", "MANUAL_MATCHED")
                ),
            )
        )
        total_revenue_vnd = int(rev_res.scalar() or 0)

        return build_fandom_ledger_response(
            fandom.id, total_revenue_vnd, orders, transactions
        )

    @staticmethod
    async def resolve_transaction_manually(
        db: AsyncSession,
        identifier: str,
        transaction_id: uuid.UUID,
        current_user: User,
        data: ManualTransactionResolveRequest,
    ) -> PaymentTransactionOut:
        """Allows the Fandom Owner to manually link & approve a discrepant transaction."""
        fandom = await FandomService._resolve_fandom(db, identifier)
        await BillingService._require_fandom_owner_or_admin(db, fandom, current_user)

        tx_res = await db.execute(
            select(PaymentTransaction)
            .where(PaymentTransaction.id == transaction_id)
            .with_for_update()
        )
        tx = tx_res.scalar_one_or_none()
        if tx is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Không tìm thấy vết giao dịch cần đối soát.",
            )

        target_code = data.order_code.strip().upper()
        order_res = await db.execute(
            select(PaymentOrder)
            .where(
                PaymentOrder.order_code == target_code,
                PaymentOrder.fandom_id == fandom.id,
            )
            .with_for_update()
        )
        order = order_res.scalar_one_or_none()
        if order is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Không tìm thấy đơn hàng '{target_code}' thuộc Fandom này.",
            )

        now = datetime.now(timezone.utc)
        order.paid_amount_vnd = (order.paid_amount_vnd or 0) + int(tx.transfer_amount)
        order.status = "PAID"
        order.paid_at = now

        tx.order_id = order.id
        tx.user_id = order.user_id
        tx.fandom_id = fandom.id
        tx.reconciliation_status = "MANUAL_MATCHED"

        provisioned_until: datetime | None = None
        if order.role_id is not None:
            provisioned_until = await BillingService._provision_membership_role_atomic(
                db, order.fandom_id, order.user_id, order.role_id, order.duration_days, now
            )

        note_suffix = f" ({data.note})" if data.note else ""
        exp_text = (
            f" Hạn hội viên đến {provisioned_until.strftime('%d/%m/%Y %H:%M UTC')}."
            if provisioned_until
            else ""
        )
        tx.audit_note = f"Đã được Chủ Fandom đối soát thủ công vào đơn {order.order_code}{note_suffix}.{exp_text}"

        await db.commit()
        await db.refresh(tx)

        await _emit_billing_event(
            fandom_id=str(order.fandom_id),
            action="membership_activated",
            target_user_id=str(order.user_id),
            order_code=order.order_code,
            order_status=order.status,
            reconciliation_status="MANUAL_MATCHED",
        )

        return serialize_transaction_out(tx, order.order_code)

    # ------------------------------------------------------------------
    # 6. Dual-Tab Membership Leaderboard (Spending & Streak)
    # ------------------------------------------------------------------

    @staticmethod
    async def get_fandom_leaderboard(
        db: AsyncSession,
        identifier: str,
        current_user: User | None = None,
        limit: int = 50,
    ) -> FandomLeaderboardOut:
        """Computes the dual-tab Fandom Leaderboard (Top Spending & Top Renewal Streak)."""
        fandom = await FandomService._resolve_fandom(db, identifier)
        now = datetime.now(timezone.utc)

        # 1. Load all Membership Tier roles for this fandom
        roles_res = await db.execute(
            select(Role).where(
                Role.fandom_id == fandom.id,
                Role.is_membership_tier.is_(True),
            )
        )
        tier_roles_by_id: dict[uuid.UUID, Role] = {
            r.id: r for r in roles_res.scalars().all()
        }

        # 2. Load all PAID / OVERPAID orders joined with User for Spending Leaderboard
        orders_res = await db.execute(
            select(PaymentOrder, User)
            .join(User, User.id == PaymentOrder.user_id)
            .where(
                PaymentOrder.fandom_id == fandom.id,
                PaymentOrder.status.in_(("PAID", "OVERPAID")),
            )
        )
        spending_by_user: dict[uuid.UUID, dict[str, object]] = {}
        for order, user in orders_res.all():
            effective_paid = int(order.paid_amount_vnd or order.amount_vnd or 0)
            role_obj = tier_roles_by_id.get(order.role_id) if order.role_id else None
            tier_level = int(role_obj.tier_level or 1) if role_obj else 1
            tier_name = role_obj.name if role_obj else order.role_name_snapshot
            tier_color = (role_obj.color_hex if role_obj else None) or "#7C4DFF"

            existing = spending_by_user.get(user.id)
            if existing is None:
                spending_by_user[user.id] = {
                    "user_id": user.id,
                    "username": user.username,
                    "display_name": user.display_name,
                    "avatar_url": user.avatar_url,
                    "total_spent_vnd": effective_paid,
                    "paid_orders_count": 1,
                    "highest_tier_name": tier_name,
                    "highest_tier_level": tier_level,
                    "highest_tier_color_hex": tier_color,
                }
            else:
                existing["total_spent_vnd"] = (
                    int(existing["total_spent_vnd"]) + effective_paid
                )
                existing["paid_orders_count"] = int(existing["paid_orders_count"]) + 1
                if tier_level >= int(existing.get("highest_tier_level") or 0):
                    existing["highest_tier_name"] = tier_name
                    existing["highest_tier_level"] = tier_level
                    existing["highest_tier_color_hex"] = tier_color

        # 3. Load all MemberRole records for Membership Tiers joined with User & Role for Streak Leaderboard
        mr_res = await db.execute(
            select(MemberRole, Role, User)
            .join(Role, Role.id == MemberRole.role_id)
            .join(User, User.id == MemberRole.user_id)
            .where(
                MemberRole.fandom_id == fandom.id,
                Role.is_membership_tier.is_(True),
            )
        )
        streak_by_user: dict[uuid.UUID, dict[str, object]] = {}
        for mr, role, user in mr_res.all():
            is_active = mr.expires_at is None or mr.expires_at > now
            candidate = {
                "user_id": user.id,
                "username": user.username,
                "display_name": user.display_name,
                "avatar_url": user.avatar_url,
                "streak_count": int(mr.streak_count or 1),
                "streak_days": int(mr.streak_days or role.duration_days or 30),
                "tier_name": role.name,
                "tier_level": int(role.tier_level or 1),
                "tier_color_hex": role.color_hex or "#7C4DFF",
                "streak_started_at": mr.streak_started_at or mr.assigned_at,
                "expires_at": mr.expires_at,
                "is_active": is_active,
            }
            existing_streak = streak_by_user.get(user.id)
            if existing_streak is None or (
                candidate["streak_count"],
                candidate["streak_days"],
                candidate["tier_level"],
            ) > (
                existing_streak["streak_count"],
                existing_streak["streak_days"],
                existing_streak["tier_level"],
            ):
                streak_by_user[user.id] = candidate

        return build_fandom_leaderboard_response(
            fandom_id=fandom.id,
            raw_spending=list(spending_by_user.values()),
            raw_streaks=list(streak_by_user.values()),
            current_user_id=current_user.id if current_user else None,
            limit=limit,
        )

