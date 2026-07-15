from __future__ import annotations

from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.admin import AdminInputError, MAX_BETA_INVITES, invite, normalize_email, revoke
from app.models import Base, BetaInvite


def test_beta_email_normalization_is_bounded() -> None:
    assert normalize_email("  Beta@Example.COM ") == "beta@example.com"
    with pytest.raises(AdminInputError):
        normalize_email("not-an-email")


@pytest.mark.asyncio
async def test_invite_upsert_and_revoke_are_idempotent(tmp_path: Path) -> None:
    database_url = f"sqlite+aiosqlite:///{tmp_path / 'admin.sqlite3'}"
    engine = create_async_engine(database_url)
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    await engine.dispose()

    first = await invite(
        database_url,
        "Beta@Example.com",
        expires_at=datetime.now(UTC) + timedelta(days=30),
    )
    second = await invite(
        database_url,
        "beta@example.com",
        expires_at=datetime.now(UTC) + timedelta(days=60),
    )
    assert first.id == second.id
    assert await revoke(database_url, "BETA@example.com") is True
    assert await revoke(database_url, "missing@example.com") is False


@pytest.mark.asyncio
async def test_invite_refuses_a_fifty_first_active_account(tmp_path: Path) -> None:
    database_url = f"sqlite+aiosqlite:///{tmp_path / 'cap.sqlite3'}"
    engine = create_async_engine(database_url)
    sessions = async_sessionmaker(engine, expire_on_commit=False)
    expiry = datetime.now(UTC) + timedelta(days=30)
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    async with sessions() as session:
        async with session.begin():
            session.add_all(
                BetaInvite(
                    email_normalized=f"beta-{index}@example.com",
                    state="invited",
                    expires_at=expiry,
                )
                for index in range(MAX_BETA_INVITES)
            )
    await engine.dispose()

    with pytest.raises(AdminInputError, match="50-user"):
        await invite(
            database_url,
            "beta-51@example.com",
            expires_at=expiry,
        )
