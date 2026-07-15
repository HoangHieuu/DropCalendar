from __future__ import annotations

from sqlalchemy import text
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from .config import ProductionSettings


class Database:
    def __init__(self, settings: ProductionSettings) -> None:
        engine_options: dict[str, object] = {"pool_pre_ping": True}
        if settings.database_url.startswith("postgresql+asyncpg://"):
            engine_options.update(
                pool_size=settings.database_pool_size,
                max_overflow=0,
                pool_timeout=10,
            )
        self.engine: AsyncEngine = create_async_engine(
            settings.database_url,
            **engine_options,
        )
        self.sessions = async_sessionmaker(
            self.engine,
            class_=AsyncSession,
            expire_on_commit=False,
            autoflush=False,
        )

    def session(self) -> AsyncSession:
        return self.sessions()

    async def is_ready(self) -> bool:
        try:
            async with self.engine.connect() as connection:
                await connection.execute(text("SELECT 1"))
            return True
        except Exception:
            return False

    async def dispose(self) -> None:
        await self.engine.dispose()

