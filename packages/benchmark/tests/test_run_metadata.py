from __future__ import annotations

import hashlib
from pathlib import Path

from snapcal_benchmark.run_metadata import build_accuracy_run_metadata


def test_builds_redacted_complete_accuracy_run_metadata(tmp_path: Path) -> None:
    manifest = tmp_path / "manifest.jsonl"
    manifest.write_text('{"schema_version":2}\n', encoding="utf-8")

    metadata = build_accuracy_run_metadata(
        manifest_path=manifest,
        preflight={
            "budget_ceiling_usd": 5.0,
            "provider_key_limit_usd": 5.0,
            "provider_key_limit_remaining_usd": 5.0,
        },
        status={
            "model": "google/gemini-3.1-flash-lite",
            "usage": {
                "request_count": 100,
                "cumulative_cost_usd": 1.25,
                "budget_remaining_usd": 3.75,
            },
        },
        score_report={
            "item_count": 100,
            "metrics": {"all": {"median_latency_ms": 4500.0}},
            "quality_gates": {"passed": True},
        },
        source_revision="abc123",
        profile="acceptance",
    )

    assert metadata["completed"] is True
    assert metadata["profile"] == "acceptance"
    assert metadata["manifest_sha256"] == hashlib.sha256(
        manifest.read_bytes()
    ).hexdigest()
    assert metadata["cumulative_cost_usd"] == 1.25
    assert metadata["provider_key_remaining_before_usd"] == 5.0
    assert metadata["provider_key_remaining_after_usd"] == 3.75
    assert metadata["privacy"]["contains_api_key"] is False
