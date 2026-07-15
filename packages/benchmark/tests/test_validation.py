from __future__ import annotations

import hashlib
import json
import base64
from dataclasses import replace
from pathlib import Path

import pytest

from snapcal_benchmark.cli import build_parser
from snapcal_benchmark import validation as validation_module
from snapcal_benchmark.validation import (
    BenchmarkValidationError,
    load_manifest,
    load_predictions,
    validate_corpus,
    validate_prediction_coverage,
)


def test_validates_image_integrity_and_safe_provenance(tmp_path: Path) -> None:
    manifest = _write_manifest(tmp_path)
    items = load_manifest(manifest)

    summary = validate_corpus(items, manifest_path=manifest)

    assert summary.total == 1
    assert summary.vietnamese_or_mixed == 1
    assert summary.challenging == 1


def test_rejects_unsanitized_item(tmp_path: Path) -> None:
    manifest = _write_manifest(tmp_path, overrides={"sanitized": False})

    with pytest.raises(BenchmarkValidationError, match="sanitized: must be true"):
        load_manifest(manifest)


def test_rejects_image_hash_mismatch(tmp_path: Path) -> None:
    manifest = _write_manifest(tmp_path, overrides={"image_sha256": "0" * 64})
    items = load_manifest(manifest)

    with pytest.raises(BenchmarkValidationError, match="SHA-256 mismatch"):
        validate_corpus(items, manifest_path=manifest)


def test_complete_gate_reports_distribution_failures(tmp_path: Path) -> None:
    manifest = _write_manifest(tmp_path)
    items = load_manifest(manifest)

    with pytest.raises(BenchmarkValidationError, match="at least 100 items"):
        validate_corpus(items, manifest_path=manifest, require_complete=True)


def test_calibration_gate_requires_exactly_twenty_items(tmp_path: Path) -> None:
    manifest = _write_manifest(tmp_path)
    items = load_manifest(manifest)

    with pytest.raises(BenchmarkValidationError, match="exactly 20 items"):
        validate_corpus(items, manifest_path=manifest, require_calibration=True)


def test_calibration_gate_accepts_exactly_twenty_hash_verified_items(tmp_path: Path) -> None:
    manifest = _write_manifest(tmp_path)
    original = load_manifest(manifest)[0]
    items = [
        replace(original, item_id=f"calibration-{index:02d}")
        for index in range(20)
    ]

    summary = validate_corpus(
        items,
        manifest_path=manifest,
        require_calibration=True,
    )

    assert summary.total == 20


def test_calibration_and_acceptance_profiles_are_mutually_exclusive(tmp_path: Path) -> None:
    manifest = _write_manifest(tmp_path)
    items = load_manifest(manifest)

    with pytest.raises(BenchmarkValidationError, match="mutually exclusive"):
        validate_corpus(
            items,
            manifest_path=manifest,
            require_complete=True,
            require_calibration=True,
        )


def test_real_world_gate_rejects_synthetic_fixture(tmp_path: Path) -> None:
    manifest = _write_manifest(tmp_path)
    items = load_manifest(manifest)

    with pytest.raises(BenchmarkValidationError, match="zero synthetic items"):
        validate_corpus(items, manifest_path=manifest, require_real_world=True)


def test_real_world_gate_accepts_owned_non_synthetic_fixture(tmp_path: Path) -> None:
    manifest = _write_manifest(tmp_path, overrides=_v2_real_world_overrides())
    items = load_manifest(manifest)

    summary = validate_corpus(
        items,
        manifest_path=manifest,
        require_real_world=True,
        require_cloud_authorized="openrouter",
        require_second_reviewed=True,
    )

    assert summary.synthetic == 0
    assert summary.non_synthetic == 1


def test_real_world_gate_rejects_legacy_non_synthetic_fixture(tmp_path: Path) -> None:
    manifest = _write_manifest(tmp_path, overrides={
        "synthetic": False,
        "provenance": {
            "kind": "owned",
            "source": "Owner-provided sanitized screenshot",
            "rights_holder": "Fixture owner",
            "license_or_permission": "Private benchmark permission",
            "redistributable": True,
        },
    })
    items = load_manifest(manifest)

    with pytest.raises(BenchmarkValidationError, match="requires manifest schema version 2"):
        validate_corpus(items, manifest_path=manifest, require_real_world=True)


def test_v2_accepts_private_external_nonredistributable_asset(tmp_path: Path) -> None:
    manifest = _write_manifest(tmp_path, overrides=_v2_real_world_overrides())
    items = load_manifest(manifest)

    summary = validate_corpus(
        items,
        manifest_path=manifest,
        require_real_world=True,
        require_cloud_authorized="openrouter",
        require_second_reviewed=True,
    )

    assert summary.total == 1
    assert items[0].provenance.redistributable is False


def test_v2_cloud_gate_rejects_missing_provider_authorization(tmp_path: Path) -> None:
    overrides = _v2_real_world_overrides()
    overrides["processing_authorization"] = {
        "benchmark_use": True,
        "cloud_processors": [],
        "authorization_reference": "permission-record-001",
    }
    manifest = _write_manifest(tmp_path, overrides=overrides)
    items = load_manifest(manifest)

    with pytest.raises(BenchmarkValidationError, match="lack openrouter processing authorization"):
        validate_corpus(
            items,
            manifest_path=manifest,
            require_cloud_authorized="openrouter",
        )


def test_v2_real_world_gate_rejects_missing_benchmark_authorization(tmp_path: Path) -> None:
    overrides = _v2_real_world_overrides()
    overrides["processing_authorization"] = {
        "benchmark_use": False,
        "cloud_processors": ["openrouter"],
        "authorization_reference": "permission-record-001",
    }
    manifest = _write_manifest(tmp_path, overrides=overrides)
    items = load_manifest(manifest)

    with pytest.raises(BenchmarkValidationError, match="lack benchmark-use authorization"):
        validate_corpus(items, manifest_path=manifest, require_real_world=True)


def test_v2_second_review_gate_rejects_unreviewed_labels(tmp_path: Path) -> None:
    overrides = _v2_real_world_overrides()
    overrides["annotation"] = {
        "critical_fields_second_reviewed": False,
        "reviewed_at": "2026-07-15T01:00:00+07:00",
    }
    manifest = _write_manifest(tmp_path, overrides=overrides)
    items = load_manifest(manifest)

    with pytest.raises(BenchmarkValidationError, match="second review"):
        validate_corpus(
            items,
            manifest_path=manifest,
            require_second_reviewed=True,
        )


def test_v2_rejects_private_image_inside_repository(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    manifest = _write_manifest(tmp_path, overrides=_v2_real_world_overrides())
    items = load_manifest(manifest)
    monkeypatch.setattr(validation_module, "REPOSITORY_ROOT", tmp_path)

    with pytest.raises(BenchmarkValidationError, match="must stay outside the repository"):
        validate_corpus(items, manifest_path=manifest)


def test_cli_exposes_authorization_and_review_gates() -> None:
    args = build_parser().parse_args([
        "validate",
        "--require-cloud-authorized",
        "openrouter",
        "--require-second-reviewed",
    ])

    assert args.require_cloud_authorized == "openrouter"
    assert args.require_second_reviewed is True

    calibration_args = build_parser().parse_args([
        "validate",
        "--require-calibration",
    ])
    assert calibration_args.require_calibration is True


def test_predictions_require_full_known_coverage(tmp_path: Path) -> None:
    manifest = _write_manifest(tmp_path)
    items = load_manifest(manifest)
    predictions_path = tmp_path / "predictions.jsonl"
    predictions_path.write_text(
        json.dumps(_prediction(item_id="unknown-item")) + "\n",
        encoding="utf-8",
    )
    predictions = load_predictions(predictions_path, mode="local_only")

    with pytest.raises(BenchmarkValidationError, match="unknown item IDs"):
        validate_prediction_coverage(items, predictions, mode="local_only")


def _write_manifest(tmp_path: Path, overrides: dict | None = None) -> Path:
    image_path = tmp_path / "images" / "vi-decorative-001.png"
    image_path.parent.mkdir()
    image_path.write_bytes(base64.b64decode(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    ))
    row = {
        "schema_version": 1,
        "id": "vi-decorative-001",
        "image": "images/vi-decorative-001.png",
        "image_sha256": hashlib.sha256(image_path.read_bytes()).hexdigest(),
        "language": "vietnamese",
        "source_category": "workshop",
        "difficulties": ["decorative_font"],
        "captured_at": "2026-07-14T09:00:00+07:00",
        "timezone": "Asia/Ho_Chi_Minh",
        "expected": {
            "title": "Hội thảo AI",
            "start": "2026-08-15T20:00:00+07:00",
            "end": "2026-08-15T22:00:00+07:00",
            "is_all_day": False,
            "location": "Đại học Bách Khoa",
        },
        "provenance": {
            "kind": "generated",
            "source": "SnapCal deterministic test fixture",
            "rights_holder": "SnapCal contributors",
            "license_or_permission": "Project test fixture",
            "redistributable": True,
        },
        "sanitized": True,
        "synthetic": True,
    }
    row.update(overrides or {})
    manifest = tmp_path / "manifest.jsonl"
    manifest.write_text(json.dumps(row, ensure_ascii=False) + "\n", encoding="utf-8")
    return manifest


def _prediction(*, item_id: str) -> dict:
    return {
        "schema_version": 1,
        "item_id": item_id,
        "mode": "local_only",
        "outcome": "failure",
        "title": None,
        "start": None,
        "end": None,
        "is_all_day": None,
        "location": None,
        "evidence_fields": [],
        "ambiguity_fields": ["extraction"],
        "latency_ms": 10,
        "failure_reason": "no_event_detected",
    }


def _v2_real_world_overrides() -> dict:
    return {
        "schema_version": 2,
        "synthetic": False,
        "provenance": {
            "kind": "permission",
            "source": "Owner-provided sanitized screenshot",
            "rights_holder": "Fixture owner",
            "license_or_permission": "Private benchmark permission",
            "redistributable": False,
        },
        "processing_authorization": {
            "benchmark_use": True,
            "cloud_processors": ["openrouter"],
            "authorization_reference": "permission-record-001",
        },
        "expected_ambiguity_fields": [],
        "annotation": {
            "critical_fields_second_reviewed": True,
            "reviewed_at": "2026-07-15T01:00:00+07:00",
        },
    }
