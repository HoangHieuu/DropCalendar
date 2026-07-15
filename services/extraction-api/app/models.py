from __future__ import annotations

import uuid
from datetime import UTC, date, datetime
from decimal import Decimal

from sqlalchemy import (
    Boolean,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    LargeBinary,
    Numeric,
    String,
    UniqueConstraint,
    Uuid,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


def utc_now() -> datetime:
    return datetime.now(UTC)


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    email_normalized: Mapped[str] = mapped_column(String(320), unique=True)
    google_subject: Mapped[str] = mapped_column(String(255), unique=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class BetaInvite(Base):
    __tablename__ = "beta_invites"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    email_normalized: Mapped[str] = mapped_column(String(320), unique=True)
    state: Mapped[str] = mapped_column(String(32), default="invited")
    activation_user_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="SET NULL")
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)
    activated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class AuthSession(Base):
    __tablename__ = "auth_sessions"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    device_identifier: Mapped[str] = mapped_column(String(255))
    refresh_token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    previous_refresh_token_hash: Mapped[str | None] = mapped_column(String(64))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)
    last_used_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)

    __table_args__ = (
        UniqueConstraint("user_id", "device_identifier", name="uq_auth_session_device"),
    )


class Plan(Base):
    __tablename__ = "plans"

    code: Mapped[str] = mapped_column(String(50), primary_key=True)
    display_name: Mapped[str] = mapped_column(String(100))
    price_usd_cents: Mapped[int] = mapped_column(Integer)
    paddle_product_id: Mapped[str | None] = mapped_column(String(100), unique=True)
    paddle_price_id: Mapped[str | None] = mapped_column(String(100), unique=True)
    monthly_quota: Mapped[int] = mapped_column(Integer)
    per_minute_limit: Mapped[int] = mapped_column(Integer, default=5)
    per_day_limit: Mapped[int] = mapped_column(Integer, default=30)
    concurrent_limit: Mapped[int] = mapped_column(Integer, default=2)
    accuracy_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)


class Subscription(Base):
    __tablename__ = "subscriptions"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), unique=True
    )
    plan_code: Mapped[str] = mapped_column(String(50), ForeignKey("plans.code"))
    paddle_customer_id: Mapped[str] = mapped_column(String(100), unique=True)
    paddle_subscription_id: Mapped[str] = mapped_column(String(100), unique=True)
    status: Mapped[str] = mapped_column(String(32))
    product_id: Mapped[str] = mapped_column(String(100))
    price_id: Mapped[str] = mapped_column(String(100))
    current_period_start: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    current_period_end: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    scheduled_change: Mapped[str | None] = mapped_column(String(32))
    scheduled_change_effective_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True)
    )
    last_event_occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)


class UsagePeriod(Base):
    __tablename__ = "usage_periods"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE")
    )
    period_start: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    period_end: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    quota_limit: Mapped[int] = mapped_column(Integer)
    reserved_units: Mapped[int] = mapped_column(Integer, default=0)
    consumed_units: Mapped[int] = mapped_column(Integer, default=0)
    actual_provider_cost_usd: Mapped[Decimal] = mapped_column(
        Numeric(12, 8), default=Decimal("0")
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)

    __table_args__ = (
        UniqueConstraint(
            "user_id", "period_start", "period_end", name="uq_usage_user_period"
        ),
        Index("ix_usage_user_period", "user_id", "period_end"),
    )


class ExtractionRequestRecord(Base):
    __tablename__ = "extraction_requests"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE")
    )
    usage_period_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("usage_periods.id", ondelete="RESTRICT")
    )
    idempotency_key: Mapped[str] = mapped_column(String(128))
    input_hmac: Mapped[str] = mapped_column(String(64))
    state: Mapped[str] = mapped_column(String(32), index=True)
    quota_reserved: Mapped[bool] = mapped_column(Boolean, default=True)
    model: Mapped[str | None] = mapped_column(String(200))
    provider_generation_id: Mapped[str | None] = mapped_column(String(255))
    input_tokens: Mapped[int | None] = mapped_column(Integer)
    output_tokens: Mapped[int | None] = mapped_column(Integer)
    provider_cost_usd: Mapped[Decimal] = mapped_column(
        Numeric(12, 8), default=Decimal("0")
    )
    provider_latency_ms: Mapped[int | None] = mapped_column(Integer)
    total_latency_ms: Mapped[int | None] = mapped_column(Integer)
    error_code: Mapped[str | None] = mapped_column(String(64))
    encrypted_result_envelope: Mapped[bytes | None] = mapped_column(LargeBinary)
    result_expires_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), index=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)
    finalized_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    __table_args__ = (
        UniqueConstraint("user_id", "idempotency_key", name="uq_extraction_idempotency"),
        Index("ix_extraction_user_created", "user_id", "created_at"),
        Index("ix_extraction_expiring_result", "result_expires_at", "state"),
    )


class WebhookEvent(Base):
    __tablename__ = "webhook_events"

    event_id: Mapped[str] = mapped_column(String(100), primary_key=True)
    event_type: Mapped[str] = mapped_column(String(100))
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    processing_state: Mapped[str] = mapped_column(String(32), default="received")
    failure_code: Mapped[str | None] = mapped_column(String(64))
    failure_count: Mapped[int] = mapped_column(Integer, default=0)
    received_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)
    processed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    __table_args__ = (
        Index("ix_webhook_unprocessed", "processing_state", "occurred_at"),
    )


class AuditEvent(Base):
    __tablename__ = "audit_events"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="SET NULL"), index=True
    )
    action: Mapped[str] = mapped_column(String(100))
    request_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    reason_code: Mapped[str | None] = mapped_column(String(64))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)


class OperationalDailyStat(Base):
    """User-free aggregate retained after 90-day request metadata deletion."""

    __tablename__ = "operational_daily_stats"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    day: Mapped[date] = mapped_column(Date)
    environment: Mapped[str] = mapped_column(String(32))
    model: Mapped[str] = mapped_column(String(200))
    state: Mapped[str] = mapped_column(String(32))
    request_count: Mapped[int] = mapped_column(Integer, default=0)
    provider_cost_usd: Mapped[Decimal] = mapped_column(
        Numeric(14, 8), default=Decimal("0")
    )
    provider_latency_ms_total: Mapped[int] = mapped_column(Integer, default=0)
    provider_latency_ms_max: Mapped[int] = mapped_column(Integer, default=0)
    total_latency_ms_total: Mapped[int] = mapped_column(Integer, default=0)
    total_latency_ms_max: Mapped[int] = mapped_column(Integer, default=0)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)

    __table_args__ = (
        UniqueConstraint(
            "day",
            "environment",
            "model",
            "state",
            name="uq_operational_daily_dimension",
        ),
    )
