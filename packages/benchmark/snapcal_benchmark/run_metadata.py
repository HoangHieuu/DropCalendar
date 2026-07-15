from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any


def build_accuracy_run_metadata(
    *,
    manifest_path: Path,
    preflight: dict[str, Any],
    status: dict[str, Any],
    score_report: dict[str, Any] | None,
    source_revision: str,
    expected_item_count: int | None = None,
    abort_reason: str | None = None,
    profile: str = "acceptance",
) -> dict[str, Any]:
    usage = _object(status.get("usage"), "status.usage")
    request_count = _integer(usage.get("request_count"), "status.usage.request_count")
    if score_report is not None:
        metrics = _object(score_report.get("metrics"), "score_report.metrics")
        all_metrics = _object(metrics.get("all"), "score_report.metrics.all")
        item_count = _integer(score_report.get("item_count"), "score_report.item_count")
        median_latency_ms = _nullable_number(
            all_metrics.get("median_latency_ms"),
            "score_report.metrics.all.median_latency_ms",
        )
        quality_gates_passed: bool | None = bool(
            _object(score_report.get("quality_gates"), "score_report.quality_gates").get(
                "passed"
            )
        )
    else:
        if expected_item_count is None:
            raise ValueError("expected_item_count is required without a score report")
        item_count = _integer(expected_item_count, "expected_item_count")
        median_latency_ms = None
        quality_gates_passed = None
    cumulative_cost_usd = _number(
        usage.get("cumulative_cost_usd"),
        "status.usage.cumulative_cost_usd",
    )
    provider_key_remaining_before_usd = _number(
        preflight.get("provider_key_limit_remaining_usd"),
        "preflight.provider_key_limit_remaining_usd",
    )
    completed = abort_reason is None and request_count == item_count
    return {
        "schema_version": 1,
        "mode": "accuracy",
        "profile": profile,
        "source_revision": source_revision,
        "manifest_sha256": _sha256(manifest_path),
        "model": _string(status.get("model"), "status.model"),
        "request_count": request_count,
        "item_count": item_count,
        "completed": completed,
        "cumulative_cost_usd": cumulative_cost_usd,
        "budget_remaining_usd": _number(
            usage.get("budget_remaining_usd"),
            "status.usage.budget_remaining_usd",
        ),
        "budget_ceiling_usd": _number(
            preflight.get("budget_ceiling_usd"),
            "preflight.budget_ceiling_usd",
        ),
        "provider_key_limit_usd": _number(
            preflight.get("provider_key_limit_usd"),
            "preflight.provider_key_limit_usd",
        ),
        "provider_key_remaining_before_usd": provider_key_remaining_before_usd,
        "provider_key_remaining_after_usd": max(
            0.0,
            provider_key_remaining_before_usd - cumulative_cost_usd,
        ),
        "median_latency_ms": median_latency_ms,
        "quality_gates_passed": quality_gates_passed,
        "abort_reason": abort_reason or (
            None if request_count == item_count else "incomplete_request_count"
        ),
        "privacy": {
            "contains_api_key": False,
            "contains_image_bytes": False,
            "contains_raw_ocr": False,
            "contains_event_values": False,
        },
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Write redacted Accuracy run metadata")
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--preflight", type=Path, required=True)
    parser.add_argument("--status", type=Path, required=True)
    parser.add_argument("--score-report", type=Path)
    parser.add_argument("--expected-item-count", type=int)
    parser.add_argument("--abort-reason")
    parser.add_argument("--source-revision", required=True)
    parser.add_argument(
        "--profile",
        choices=("calibration", "acceptance", "regression"),
        default="acceptance",
    )
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    metadata = build_accuracy_run_metadata(
        manifest_path=args.manifest,
        preflight=_read_json(args.preflight),
        status=_read_json(args.status),
        score_report=_read_json(args.score_report) if args.score_report else None,
        source_revision=args.source_revision,
        expected_item_count=args.expected_item_count,
        abort_reason=args.abort_reason,
        profile=args.profile,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return 0


def _read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    return _object(value, str(path))


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _object(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{label} must be an object")
    return value


def _string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{label} must be a non-empty string")
    return value.strip()


def _integer(value: Any, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise ValueError(f"{label} must be a non-negative integer")
    return value


def _number(value: Any, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or value < 0:
        raise ValueError(f"{label} must be a non-negative number")
    return float(value)


def _nullable_number(value: Any, label: str) -> float | None:
    if value is None:
        return None
    return _number(value, label)


if __name__ == "__main__":
    raise SystemExit(main())
