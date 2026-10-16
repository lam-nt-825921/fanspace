import uuid
from datetime import datetime
from pydantic import BaseModel, Field


class FandomCreate(BaseModel):
    name: str = Field(min_length=2, max_length=100)
    slug: str = Field(min_length=2, max_length=100, pattern=r"^[a-z0-9-]+$")
    description: str | None = None
    category: str = Field(default="Music", max_length=50)
    avatar_url: str | None = None
    banner_url: str | None = None
    admission_mode: str = Field(default="OPEN", pattern=r"^(OPEN|APPROVAL)$")
    rules_tos: str | None = None


class FandomSummary(BaseModel):
    id: uuid.UUID
    name: str
    slug: str
    description: str | None = None
    category: str
    avatar_url: str | None = None
    banner_url: str | None = None
    member_count: int
    owner_name: str
    created_at: datetime

    model_config = {"from_attributes": True}


class FandomDetail(BaseModel):
    id: uuid.UUID
    name: str
    slug: str
    description: str | None = None
    category: str
    avatar_url: str | None = None
    banner_url: str | None = None
    admission_mode: str
    rules_tos: str | None = None
    member_count: int
    owner_id: uuid.UUID
    owner_name: str
    is_owner: bool = False
    is_member: bool = False
    created_at: datetime

    model_config = {"from_attributes": True}
