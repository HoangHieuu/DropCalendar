from __future__ import annotations

import hashlib
import json
import base64
from pathlib import Path

import pytest

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


def test_real_world_gate_rejects_synthetic_fixture(tmp_path: Path) -> None:
    manifest = _write_manifest(tmp_path)
    items = load_manifest(manifest)

    with pytest.raises(BenchmarkValidationError, match="zero synthetic items"):
        validate_corpus(items, manifest_path=manifest, require_real_world=True)


def test_real_world_gate_accepts_owned_non_synthetic_fixture(tmp_path: Path) -> None:
    manifest = _write_manifest(tmp_path, overrides={
        "synthetic": False,
        "provenance": {
            "kind": "owned",
            "source": "Owner-provided sanitized screenshot",
            "rights_holder": "Fixture owner",
            "license_or_permission": "Owner permission for benchmark redistribution",
            "redistributable": True,
        },
    })
    items = load_manifest(manifest)

    summary = validate_corpus(items, manifest_path=manifest, require_real_world=True)

    assert summary.synthetic == 0
    assert summary.non_synthetic == 1


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
