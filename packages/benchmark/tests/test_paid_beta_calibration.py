from __future__ import annotations

import json
from pathlib import Path

import pytest

from packages.benchmark.tools.check_paid_beta_calibration import check


def write_rows(path: Path, *, cost: float, latency_ms: float, count: int = 20) -> None:
    path.write_text(
        "".join(
            json.dumps(
                {
                    "item_id": f"fixture-{index}",
                    "request_cost_usd": cost,
                    "latency_ms": latency_ms,
                    "succeeded": True,
                }
            )
            + "\n"
            for index in range(count)
        )
    )


def test_paid_beta_calibration_accepts_all_locked_cost_and_latency_gates(
    tmp_path: Path,
) -> None:
    records = tmp_path / "records.jsonl"
    write_rows(records, cost=0.0049, latency_ms=4_900)
    report = check(records)
    assert report["request_count"] == 20
    assert report["passed"] is True
    assert all(report["gates"].values())


def test_paid_beta_calibration_fails_closed_on_count_or_cost(tmp_path: Path) -> None:
    records = tmp_path / "records.jsonl"
    write_rows(records, cost=0.001, latency_ms=100, count=19)
    with pytest.raises(ValueError, match="exactly 20"):
        check(records)

    write_rows(records, cost=0.006, latency_ms=100)
    report = check(records)
    assert report["passed"] is False
    assert report["gates"]["mean_cost"] is False
    assert report["gates"]["projected_100_cost"] is False
