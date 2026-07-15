from __future__ import annotations

import argparse
import hashlib
import json
import sys
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation, ROUND_UP
from pathlib import Path
from typing import Any


MAX_AUTHORIZED_TOTAL_USD = Decimal("5.00")
CALIBRATION_ITEM_COUNT = 20
ACCEPTANCE_MINIMUM_ITEM_COUNT = 100
SAFETY_RESERVE_FRACTION = Decimal("0.20")
MINIMUM_PROCESS_BUDGET_USD = Decimal("0.01")
MONEY_QUANTUM = Decimal("0.000001")


class AccuracyPipelineError(ValueError):
    pass


def build_manifest_freeze(
    *,
    manifest_path: Path,
    item_count: int,
    source_revision: str,
) -> dict[str, Any]:
    if item_count < ACCEPTANCE_MINIMUM_ITEM_COUNT:
        raise AccuracyPipelineError(
            f"acceptance freeze requires at least {ACCEPTANCE_MINIMUM_ITEM_COUNT} items"
        )
    return {
        "schema_version": 1,
        "frozen": True,
        "manifest_sha256": _sha256(manifest_path),
        "item_count": item_count,
        "source_revision": _nonempty_string(source_revision, "source_revision"),
        "frozen_at": datetime.now(timezone.utc).isoformat(),
        "privacy": {
            "contains_image_bytes": False,
            "contains_raw_ocr": False,
            "contains_event_values": False,
        },
    }


def verify_manifest_freeze(*, manifest_path: Path, freeze: dict[str, Any]) -> None:
    if freeze.get("frozen") is not True:
        raise AccuracyPipelineError("acceptance freeze is not marked frozen")
    expected_hash = _nonempty_string(freeze.get("manifest_sha256"), "manifest_sha256")
    if _sha256(manifest_path) != expected_hash:
        raise AccuracyPipelineError("acceptance manifest changed after it was frozen")


def build_cost_projection(
    *,
    calibration_metadata: dict[str, Any],
    acceptance_item_count: int,
    total_budget_usd: Decimal | str = MAX_AUTHORIZED_TOTAL_USD,
) -> dict[str, Any]:
    total_budget = _decimal(total_budget_usd, "total_budget_usd")
    if total_budget <= 0 or total_budget > MAX_AUTHORIZED_TOTAL_USD:
        raise AccuracyPipelineError("total budget must be positive and no greater than $5")
    if acceptance_item_count < ACCEPTANCE_MINIMUM_ITEM_COUNT:
        raise AccuracyPipelineError(
            f"acceptance projection requires at least {ACCEPTANCE_MINIMUM_ITEM_COUNT} items"
        )
    if calibration_metadata.get("completed") is not True:
        raise AccuracyPipelineError("calibration run must be complete before projection")
    if calibration_metadata.get("profile") != "calibration":
        raise AccuracyPipelineError("cost projection requires calibration run metadata")
    item_count = _integer(calibration_metadata.get("item_count"), "calibration.item_count")
    request_count = _integer(
        calibration_metadata.get("request_count"), "calibration.request_count"
    )
    if item_count != CALIBRATION_ITEM_COUNT or request_count != CALIBRATION_ITEM_COUNT:
        raise AccuracyPipelineError(
            f"calibration must contain exactly {CALIBRATION_ITEM_COUNT} completed requests"
        )

    calibration_cost = _decimal(
        calibration_metadata.get("cumulative_cost_usd"),
        "calibration.cumulative_cost_usd",
    )
    provider_remaining = _decimal(
        calibration_metadata.get("provider_key_remaining_after_usd"),
        "calibration.provider_key_remaining_after_usd",
    )
    authorized_remaining = max(Decimal("0"), total_budget - calibration_cost)
    usable_remaining = min(authorized_remaining, provider_remaining)
    per_item_cost = calibration_cost / Decimal(CALIBRATION_ITEM_COUNT)
    projected_base = per_item_cost * Decimal(acceptance_item_count)
    reserve = projected_base * SAFETY_RESERVE_FRACTION
    projected_with_reserve = max(
        MINIMUM_PROCESS_BUDGET_USD,
        (projected_base + reserve).quantize(MONEY_QUANTUM, rounding=ROUND_UP),
    )
    approved = projected_with_reserve <= usable_remaining

    return {
        "schema_version": 1,
        "approved": approved,
        "calibration_item_count": item_count,
        "acceptance_item_count": acceptance_item_count,
        "calibration_cost_usd": float(calibration_cost),
        "calibration_cost_per_item_usd": float(per_item_cost),
        "projected_acceptance_cost_usd": float(projected_base),
        "safety_reserve_fraction": float(SAFETY_RESERVE_FRACTION),
        "safety_reserve_usd": float(reserve),
        "acceptance_budget_usd": float(projected_with_reserve) if approved else 0.0,
        "total_authorized_budget_usd": float(total_budget),
        "authorized_budget_remaining_usd": float(authorized_remaining),
        "provider_key_remaining_usd": float(provider_remaining),
        "usable_remaining_usd": float(usable_remaining),
        "abort_reason": None if approved else "projected_cost_with_reserve_exceeds_remaining_budget",
        "privacy": {
            "contains_api_key": False,
            "contains_image_bytes": False,
            "contains_raw_ocr": False,
            "contains_event_values": False,
        },
    }


def build_pipeline_metadata(
    *,
    calibration_metadata: dict[str, Any],
    acceptance_metadata: dict[str, Any],
    projection: dict[str, Any],
    freeze: dict[str, Any],
) -> dict[str, Any]:
    calibration_cost = _decimal(
        calibration_metadata.get("cumulative_cost_usd"),
        "calibration.cumulative_cost_usd",
    )
    acceptance_cost = _decimal(
        acceptance_metadata.get("cumulative_cost_usd"),
        "acceptance.cumulative_cost_usd",
    )
    acceptance_budget = _decimal(
        projection.get("acceptance_budget_usd"),
        "projection.acceptance_budget_usd",
    )
    total_budget = _decimal(
        projection.get("total_authorized_budget_usd"),
        "projection.total_authorized_budget_usd",
    )
    total_cost = calibration_cost + acceptance_cost
    calibration_count = _integer(
        calibration_metadata.get("item_count"), "calibration.item_count"
    )
    acceptance_count = _integer(
        acceptance_metadata.get("item_count"), "acceptance.item_count"
    )
    same_model = calibration_metadata.get("model") == acceptance_metadata.get("model")
    frozen_hash_matches = (
        freeze.get("manifest_sha256") == acceptance_metadata.get("manifest_sha256")
    )
    checks = {
        "projection_approved": projection.get("approved") is True,
        "calibration_complete": calibration_metadata.get("completed") is True,
        "calibration_item_count": calibration_count == CALIBRATION_ITEM_COUNT,
        "acceptance_complete": acceptance_metadata.get("completed") is True,
        "acceptance_item_count": acceptance_count >= ACCEPTANCE_MINIMUM_ITEM_COUNT,
        "acceptance_quality_gates": acceptance_metadata.get("quality_gates_passed") is True,
        "acceptance_within_projected_budget": acceptance_cost <= acceptance_budget,
        "combined_cost_within_authorized_budget": total_cost <= total_budget,
        "fixed_model": same_model,
        "frozen_acceptance_manifest": freeze.get("frozen") is True and frozen_hash_matches,
    }
    return {
        "schema_version": 1,
        "completed": all(checks.values()),
        "checks": checks,
        "model": acceptance_metadata.get("model") if same_model else None,
        "calibration_manifest_sha256": calibration_metadata.get("manifest_sha256"),
        "acceptance_manifest_sha256": acceptance_metadata.get("manifest_sha256"),
        "calibration_item_count": calibration_count,
        "acceptance_item_count": acceptance_count,
        "calibration_request_count": calibration_metadata.get("request_count"),
        "acceptance_request_count": acceptance_metadata.get("request_count"),
        "calibration_cost_usd": float(calibration_cost),
        "acceptance_cost_usd": float(acceptance_cost),
        "combined_cost_usd": float(total_cost),
        "total_authorized_budget_usd": float(total_budget),
        "privacy": {
            "contains_api_key": False,
            "contains_image_bytes": False,
            "contains_raw_ocr": False,
            "contains_event_values": False,
        },
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Orchestrate redacted Accuracy benchmark gates")
    subparsers = parser.add_subparsers(dest="command", required=True)

    freeze = subparsers.add_parser("freeze")
    freeze.add_argument("--manifest", type=Path, required=True)
    freeze.add_argument("--item-count", type=int, required=True)
    freeze.add_argument("--source-revision", required=True)
    freeze.add_argument("--output", type=Path, required=True)

    verify = subparsers.add_parser("verify-freeze")
    verify.add_argument("--manifest", type=Path, required=True)
    verify.add_argument("--freeze", type=Path, required=True)

    project = subparsers.add_parser("project")
    project.add_argument("--calibration-metadata", type=Path, required=True)
    project.add_argument("--acceptance-item-count", type=int, required=True)
    project.add_argument("--total-budget-usd", default="5.00")
    project.add_argument("--output", type=Path, required=True)

    finalize = subparsers.add_parser("finalize")
    finalize.add_argument("--calibration-metadata", type=Path, required=True)
    finalize.add_argument("--acceptance-metadata", type=Path, required=True)
    finalize.add_argument("--projection", type=Path, required=True)
    finalize.add_argument("--freeze", type=Path, required=True)
    finalize.add_argument("--output", type=Path, required=True)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.command == "freeze":
            result = build_manifest_freeze(
                manifest_path=args.manifest,
                item_count=args.item_count,
                source_revision=args.source_revision,
            )
            if args.output.exists():
                existing = _read_json(args.output)
                if (
                    existing.get("manifest_sha256") != result["manifest_sha256"]
                    or existing.get("item_count") != result["item_count"]
                ):
                    raise AccuracyPipelineError(
                        "existing acceptance freeze does not match the current manifest"
                    )
                result = existing
            _write_json(args.output, result)
        elif args.command == "verify-freeze":
            verify_manifest_freeze(
                manifest_path=args.manifest,
                freeze=_read_json(args.freeze),
            )
            result = {"frozen": True, "verified": True}
        elif args.command == "project":
            result = build_cost_projection(
                calibration_metadata=_read_json(args.calibration_metadata),
                acceptance_item_count=args.acceptance_item_count,
                total_budget_usd=args.total_budget_usd,
            )
            _write_json(args.output, result)
            if not result["approved"]:
                print(json.dumps(result, sort_keys=True))
                return 2
        else:
            result = build_pipeline_metadata(
                calibration_metadata=_read_json(args.calibration_metadata),
                acceptance_metadata=_read_json(args.acceptance_metadata),
                projection=_read_json(args.projection),
                freeze=_read_json(args.freeze),
            )
            _write_json(args.output, result)
            if not result["completed"]:
                print(json.dumps(result, sort_keys=True))
                return 2
    except (OSError, json.JSONDecodeError, AccuracyPipelineError) as error:
        print(f"accuracy pipeline failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


def _read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise AccuracyPipelineError(f"{path} must contain a JSON object")
    return value


def _write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _decimal(value: Any, label: str) -> Decimal:
    if isinstance(value, bool):
        raise AccuracyPipelineError(f"{label} must be a non-negative number")
    try:
        parsed = Decimal(str(value))
    except (InvalidOperation, ValueError) as error:
        raise AccuracyPipelineError(f"{label} must be a non-negative number") from error
    if not parsed.is_finite() or parsed < 0:
        raise AccuracyPipelineError(f"{label} must be a non-negative number")
    return parsed


def _integer(value: Any, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise AccuracyPipelineError(f"{label} must be a non-negative integer")
    return value


def _nonempty_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise AccuracyPipelineError(f"{label} must be a non-empty string")
    return value.strip()


if __name__ == "__main__":
    raise SystemExit(main())
