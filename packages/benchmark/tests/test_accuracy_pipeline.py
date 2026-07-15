from __future__ import annotations

import hashlib
from pathlib import Path

import pytest

from snapcal_benchmark.accuracy_pipeline import (
    AccuracyPipelineError,
    build_cost_projection,
    build_manifest_freeze,
    build_pipeline_metadata,
    verify_manifest_freeze,
)


def calibration_metadata(**overrides: object) -> dict[str, object]:
    value: dict[str, object] = {
        "profile": "calibration",
        "completed": True,
        "item_count": 20,
        "request_count": 20,
        "cumulative_cost_usd": 0.20,
        "provider_key_remaining_after_usd": 4.80,
        "model": "google/gemini-3.1-flash-lite",
        "manifest_sha256": "a" * 64,
    }
    value.update(overrides)
    return value


def test_projects_acceptance_cost_with_twenty_percent_reserve() -> None:
    projection = build_cost_projection(
        calibration_metadata=calibration_metadata(),
        acceptance_item_count=100,
    )

    assert projection["approved"] is True
    assert projection["projected_acceptance_cost_usd"] == 1.0
    assert projection["safety_reserve_usd"] == 0.2
    assert projection["acceptance_budget_usd"] == 1.2
    assert projection["usable_remaining_usd"] == 4.8


def test_rejects_projection_that_cannot_fit_under_remaining_five_dollars() -> None:
    projection = build_cost_projection(
        calibration_metadata=calibration_metadata(
            cumulative_cost_usd=1.0,
            provider_key_remaining_after_usd=4.0,
        ),
        acceptance_item_count=100,
    )

    assert projection["approved"] is False
    assert projection["acceptance_budget_usd"] == 0.0
    assert projection["abort_reason"] == "projected_cost_with_reserve_exceeds_remaining_budget"


def test_projection_requires_complete_twenty_item_calibration() -> None:
    with pytest.raises(AccuracyPipelineError, match="exactly 20 completed requests"):
        build_cost_projection(
            calibration_metadata=calibration_metadata(request_count=19),
            acceptance_item_count=100,
        )


def test_freeze_detects_acceptance_manifest_changes(tmp_path: Path) -> None:
    manifest = tmp_path / "manifest.jsonl"
    manifest.write_text('{"id":"one"}\n', encoding="utf-8")
    freeze = build_manifest_freeze(
        manifest_path=manifest,
        item_count=100,
        source_revision="abc123",
    )

    assert freeze["manifest_sha256"] == hashlib.sha256(manifest.read_bytes()).hexdigest()
    verify_manifest_freeze(manifest_path=manifest, freeze=freeze)

    manifest.write_text('{"id":"changed"}\n', encoding="utf-8")
    with pytest.raises(AccuracyPipelineError, match="changed after it was frozen"):
        verify_manifest_freeze(manifest_path=manifest, freeze=freeze)


def test_final_metadata_requires_budget_quality_model_and_freeze_checks() -> None:
    calibration = calibration_metadata()
    projection = build_cost_projection(
        calibration_metadata=calibration,
        acceptance_item_count=100,
    )
    acceptance = {
        "completed": True,
        "item_count": 100,
        "request_count": 100,
        "cumulative_cost_usd": 1.0,
        "quality_gates_passed": True,
        "model": "google/gemini-3.1-flash-lite",
        "manifest_sha256": "b" * 64,
    }
    freeze = {"frozen": True, "manifest_sha256": "b" * 64}

    result = build_pipeline_metadata(
        calibration_metadata=calibration,
        acceptance_metadata=acceptance,
        projection=projection,
        freeze=freeze,
    )

    assert result["completed"] is True
    assert result["combined_cost_usd"] == 1.2
    assert all(result["checks"].values())
