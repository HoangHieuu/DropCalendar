from __future__ import annotations

import argparse
import asyncio
import os
import re
from datetime import UTC, datetime, timedelta

from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from .models import AuditEvent, BetaInvite


MAX_BETA_INVITES = 50
EMAIL_PATTERN = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")
INVITE_LOCK_KEY = 7_250_426_311


class AdminInputError(ValueError):
    pass


def normalize_email(value: str) -> str:
    normalized = value.strip().casefold()
    if len(normalized) > 320 or EMAIL_PATTERN.fullmatch(normalized) is None:
        raise AdminInputError("a valid beta email is required")
    return normalized


async def invite(
    database_url: str,
    email: str,
    *,
    expires_at: datetime,
) -> BetaInvite:
    normalized = normalize_email(email)
    now = datetime.now(UTC)
    if expires_at.tzinfo is None or expires_at.astimezone(UTC) <= now:
        raise AdminInputError("invite expiry must be in the future")
    engine = create_async_engine(database_url, pool_pre_ping=True)
    sessions = async_sessionmaker(engine, expire_on_commit=False)
    try:
        async with sessions() as session:
            async with session.begin():
                if database_url.startswith("postgresql+asyncpg://"):
                    await session.execute(
                        text("SELECT pg_advisory_xact_lock(:key)"),
                        {"key": INVITE_LOCK_KEY},
                    )
                existing = await session.scalar(
                    select(BetaInvite)
                    .where(BetaInvite.email_normalized == normalized)
                    .with_for_update()
                )
                existing_is_active = (
                    existing is not None
                    and existing.state in {"invited", "activated"}
                    and _utc(existing.expires_at) > now
                )
                if not existing_is_active:
                    active_count = await session.scalar(
                        select(func.count())
                        .select_from(BetaInvite)
                        .where(
                            BetaInvite.state.in_({"invited", "activated"}),
                            BetaInvite.expires_at > now,
                        )
                    )
                    if int(active_count or 0) >= MAX_BETA_INVITES:
                        raise AdminInputError("the 50-user beta invite cap is reached")
                if existing is None:
                    existing = BetaInvite(
                        email_normalized=normalized,
                        state="invited",
                        expires_at=expires_at.astimezone(UTC),
                    )
                    session.add(existing)
                else:
                    existing.expires_at = expires_at.astimezone(UTC)
                    if existing.state == "revoked":
                        existing.state = "invited"
                        existing.activation_user_id = None
                        existing.activated_at = None
                session.add(
                    AuditEvent(
                        user_id=None,
                        action="beta_invite_upserted",
                        reason_code=None,
                        expires_at=now + timedelta(days=90),
                    )
                )
                await session.flush()
        return existing
    finally:
        await engine.dispose()


async def revoke(database_url: str, email: str) -> bool:
    normalized = normalize_email(email)
    now = datetime.now(UTC)
    engine = create_async_engine(database_url, pool_pre_ping=True)
    sessions = async_sessionmaker(engine, expire_on_commit=False)
    try:
        async with sessions() as session:
            async with session.begin():
                record = await session.scalar(
                    select(BetaInvite)
                    .where(BetaInvite.email_normalized == normalized)
                    .with_for_update()
                )
                if record is None:
                    return False
                record.state = "revoked"
                session.add(
                    AuditEvent(
                        user_id=record.activation_user_id,
                        action="beta_invite_revoked",
                        reason_code=None,
                        expires_at=now + timedelta(days=90),
                    )
                )
        return True
    finally:
        await engine.dispose()


async def active_invite_count(database_url: str) -> int:
    now = datetime.now(UTC)
    engine = create_async_engine(database_url, pool_pre_ping=True)
    sessions = async_sessionmaker(engine, expire_on_commit=False)
    try:
        async with sessions() as session:
            count = await session.scalar(
                select(func.count())
                .select_from(BetaInvite)
                .where(
                    BetaInvite.state.in_({"invited", "activated"}),
                    BetaInvite.expires_at > now,
                )
            )
        return int(count or 0)
    finally:
        await engine.dispose()


def main() -> int:
    parser = argparse.ArgumentParser(description="Manage SnapCal's capped paid beta")
    parser.add_argument(
        "--database-url",
        default=os.environ.get("DATABASE_URL", ""),
        help="Async SQLAlchemy URL; defaults to DATABASE_URL.",
    )
    commands = parser.add_subparsers(dest="command", required=True)
    invite_parser = commands.add_parser("invite")
    invite_parser.add_argument("email")
    invite_parser.add_argument("--days", type=int, default=30)
    revoke_parser = commands.add_parser("revoke")
    revoke_parser.add_argument("email")
    commands.add_parser("count")
    args = parser.parse_args()
    if not args.database_url.startswith(("postgresql+asyncpg://", "sqlite+aiosqlite://")):
        parser.error("--database-url must use an async SQLAlchemy driver")
    try:
        if args.command == "invite":
            if not 1 <= args.days <= 365:
                raise AdminInputError("--days must be between 1 and 365")
            record = asyncio.run(
                invite(
                    args.database_url,
                    args.email,
                    expires_at=datetime.now(UTC) + timedelta(days=args.days),
                )
            )
            count = asyncio.run(active_invite_count(args.database_url))
            print(f"invite={record.state} active={count}/{MAX_BETA_INVITES}")
        elif args.command == "revoke":
            changed = asyncio.run(revoke(args.database_url, args.email))
            count = asyncio.run(active_invite_count(args.database_url))
            print(f"revoked={str(changed).lower()} active={count}/{MAX_BETA_INVITES}")
        else:
            print(
                f"active={asyncio.run(active_invite_count(args.database_url))}/{MAX_BETA_INVITES}"
            )
    except AdminInputError as error:
        parser.error(str(error))
    return 0


def _utc(value: datetime) -> datetime:
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)


if __name__ == "__main__":
    raise SystemExit(main())
