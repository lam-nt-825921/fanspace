"""Tests for Fandom receiving bank account registration and SePay connector activation."""

import uuid
import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import AsyncSessionLocal
from app.modules.billing.models import FandomBankAccount
from app.modules.billing.schemas import FandomBankAccountUpsert
from app.modules.billing.service import BillingService
from app.modules.fandom.models import Fandom
from app.modules.identity.models import User


@pytest.mark.asyncio
async def test_upsert_bank_account_triggers_sepay_activation():
    """Verifies that upserting a bank account triggers SePay connector and persists activation metadata."""
    async with AsyncSessionLocal() as db:
        # 1. Create a dummy test user and fandom
        test_suffix = uuid.uuid4().hex[:8]
        owner = User(
            id=uuid.uuid4(),
            email=f"owner_{test_suffix}@test.com",
            username=f"owner_{test_suffix}",
            password_hash="argon2_fake_hash",
            display_name=f"Owner {test_suffix}",
        )
        db.add(owner)
        await db.commit()

        fandom = Fandom(
            id=uuid.uuid4(),
            name=f"Fandom {test_suffix}",
            slug=f"fandom-{test_suffix}",
            owner_id=owner.id,
            description="Testing bank account activation",
        )
        db.add(fandom)
        await db.commit()

        # 2. Upsert bank account with pre-registered sandbox account (MBBank 6280793157)
        data = FandomBankAccountUpsert(
            bank_code="MBBank",
            account_number="6280793157",
            account_name="NGUYEN TUNG LAM",
            is_active=True,
        )

        res = await BillingService.upsert_bank_account(
            db=db,
            identifier=str(fandom.id),
            current_user=owner,
            data=data,
        )

        assert res.fandom_id == fandom.id
        assert res.bank_code == "MBBank"
        assert res.account_number == "6280793157"
        assert res.account_name == "NGUYEN TUNG LAM"
        assert res.is_active is True
        assert res.is_verified is True
        assert res.sepay_account_id == "4873ef39-e3e6-11f1-8895-0afffe87053b"
        assert res.activation_mode == "sandbox_token"
        assert res.verified_at is not None
        assert "MBBank" in (res.activation_note or "")

        # 3. Verify in database
        db_res = await db.execute(
            select(FandomBankAccount).where(FandomBankAccount.fandom_id == fandom.id)
        )
        saved_acc = db_res.scalar_one_or_none()
        assert saved_acc is not None
        assert saved_acc.sepay_account_id == "4873ef39-e3e6-11f1-8895-0afffe87053b"
        assert saved_acc.activation_mode == "sandbox_token"
        assert saved_acc.is_verified is True
