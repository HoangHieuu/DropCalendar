from __future__ import annotations

import asyncio
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation

from .contracts import ExtractionRequest
from .provider import (
    BenchmarkExtractionProvider,
    InvalidProviderOutputError,
    ProviderExtractionResult,
    ProviderKeyStatus,
    ProviderUsageUnavailableError,
)


MAX_AUTHORIZED_BUDGET_USD = Decimal("5.00")


class BenchmarkConfigurationError(ValueError):
    pass


class BenchmarkPreflightError(RuntimeError):
    pass


class BenchmarkBudgetExceededError(RuntimeError):
    pass


@dataclass(frozen=True)
class BenchmarkPreflightSnapshot:
    budget_ceiling_usd: Decimal
    provider_key_limit_usd: Decimal
    provider_key_limit_remaining_usd: Decimal
    provider_key_limit_reset: str | None


@dataclass(frozen=True)
class BenchmarkUsageSnapshot:
    request_cost_usd: Decimal
    cumulative_cost_usd: Decimal
    budget_remaining_usd: Decimal
    request_count: int


class BenchmarkBudget:
    def __init__(self, ceiling_usd: Decimal | str) -> None:
        try:
            ceiling = Decimal(str(ceiling_usd))
        except InvalidOperation as error:
            raise BenchmarkConfigurationError("benchmark budget must be a number") from error
        if not ceiling.is_finite() or ceiling <= 0:
            raise BenchmarkConfigurationError("benchmark budget must be positive")
        if ceiling > MAX_AUTHORIZED_BUDGET_USD:
            raise BenchmarkConfigurationError(
                f"benchmark budget cannot exceed ${MAX_AUTHORIZED_BUDGET_USD}"
            )
        self.ceiling_usd = ceiling
        self._cumulative_cost_usd = Decimal("0")
        self._request_count = 0
        self._preflight: BenchmarkPreflightSnapshot | None = None
        self._lock = asyncio.Lock()

    async def preflight(
        self, provider: BenchmarkExtractionProvider
    ) -> BenchmarkPreflightSnapshot:
        async with self._lock:
            return await self._preflight_locked(provider)

    async def extract(
        self,
        provider: BenchmarkExtractionProvider,
        request: ExtractionRequest,
    ) -> tuple[ProviderExtractionResult, BenchmarkUsageSnapshot]:
        async with self._lock:
            if self._preflight is None:
                await self._preflight_locked(provider)
            if self._cumulative_cost_usd >= self.ceiling_usd:
                raise BenchmarkBudgetExceededError("benchmark budget is exhausted")

            try:
                result = await provider.extract_with_usage(request)
            except InvalidProviderOutputError as error:
                accounting = error.accounting
                request_cost = accounting.request_cost_usd if accounting else None
                if request_cost is None:
                    raise ProviderUsageUnavailableError(
                        "invalid benchmark output omitted request cost",
                        accounting=accounting,
                    ) from error
                self._record_cost(request_cost)
                raise
            if (
                not result.request_cost_usd.is_finite()
                or result.request_cost_usd < 0
            ):
                raise ProviderUsageUnavailableError(
                    "benchmark provider returned an invalid request cost"
                )
            usage = self._record_cost(result.request_cost_usd)
            return result, usage

    async def status(self) -> BenchmarkUsageSnapshot:
        async with self._lock:
            return self._usage_snapshot(Decimal("0"))

    async def _preflight_locked(
        self, provider: BenchmarkExtractionProvider
    ) -> BenchmarkPreflightSnapshot:
        if self._preflight is not None:
            return self._preflight
        key_status = await provider.key_status()
        self._preflight = self._validate_key_status(key_status)
        return self._preflight

    def _validate_key_status(
        self, key_status: ProviderKeyStatus
    ) -> BenchmarkPreflightSnapshot:
        if key_status.limit_usd is None:
            raise BenchmarkPreflightError(
                "benchmark API key must have a provider-side spending limit"
            )
        if key_status.limit_usd > MAX_AUTHORIZED_BUDGET_USD:
            raise BenchmarkPreflightError(
                "benchmark API key limit exceeds the authorized $5 ceiling"
            )
        if key_status.limit_remaining_usd is None:
            raise BenchmarkPreflightError(
                "benchmark API key must report a finite remaining limit"
            )
        if key_status.limit_remaining_usd < self.ceiling_usd:
            raise BenchmarkPreflightError(
                "benchmark API key does not have the configured process budget remaining"
            )
        return BenchmarkPreflightSnapshot(
            budget_ceiling_usd=self.ceiling_usd,
            provider_key_limit_usd=key_status.limit_usd,
            provider_key_limit_remaining_usd=key_status.limit_remaining_usd,
            provider_key_limit_reset=key_status.limit_reset,
        )

    def _usage_snapshot(self, request_cost_usd: Decimal) -> BenchmarkUsageSnapshot:
        remaining = max(
            Decimal("0"),
            self.ceiling_usd - self._cumulative_cost_usd,
        )
        return BenchmarkUsageSnapshot(
            request_cost_usd=request_cost_usd,
            cumulative_cost_usd=self._cumulative_cost_usd,
            budget_remaining_usd=remaining,
            request_count=self._request_count,
        )

    def _record_cost(self, request_cost_usd: Decimal) -> BenchmarkUsageSnapshot:
        if not request_cost_usd.is_finite() or request_cost_usd < 0:
            raise ProviderUsageUnavailableError(
                "benchmark provider returned an invalid request cost"
            )
        self._request_count += 1
        self._cumulative_cost_usd += request_cost_usd
        usage = self._usage_snapshot(request_cost_usd)
        if self._cumulative_cost_usd > self.ceiling_usd:
            raise BenchmarkBudgetExceededError(
                "benchmark request exceeded the remaining process budget"
            )
        return usage
