from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .metrics import score_predictions, write_report
from .validation import (
    BenchmarkValidationError,
    load_manifest,
    load_predictions,
    validate_corpus,
)


DEFAULT_MANIFEST = Path("packages/benchmark/corpus/manifest.jsonl")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Validate and score SnapCal extraction benchmarks")
    subparsers = parser.add_subparsers(dest="command", required=True)

    validate_parser = subparsers.add_parser("validate", help="validate corpus integrity")
    validate_parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    validate_parser.add_argument("--require-complete", action="store_true")
    validate_parser.add_argument("--require-calibration", action="store_true")
    validate_parser.add_argument("--require-real-world", action="store_true")
    validate_parser.add_argument(
        "--require-cloud-authorized",
        choices=("openrouter",),
    )
    validate_parser.add_argument("--require-second-reviewed", action="store_true")

    score_parser = subparsers.add_parser("score", help="score versioned predictions")
    score_parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    score_parser.add_argument("--predictions", type=Path, required=True)
    score_parser.add_argument("--mode", choices=("local_only", "accuracy"), required=True)
    score_parser.add_argument("--output", type=Path, required=True)
    score_parser.add_argument("--require-complete", action="store_true")
    score_parser.add_argument("--require-calibration", action="store_true")
    score_parser.add_argument("--require-real-world", action="store_true")
    score_parser.add_argument(
        "--require-cloud-authorized",
        choices=("openrouter",),
    )
    score_parser.add_argument("--require-second-reviewed", action="store_true")
    score_parser.add_argument("--enforce-gates", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        items = load_manifest(args.manifest)
        summary = validate_corpus(
            items,
            manifest_path=args.manifest,
            require_complete=args.require_complete,
            require_calibration=args.require_calibration,
            require_real_world=args.require_real_world,
            require_cloud_authorized=args.require_cloud_authorized,
            require_second_reviewed=args.require_second_reviewed,
        )
        if args.command == "validate":
            print(json.dumps(summary.as_dict(), sort_keys=True))
            return 0

        predictions = load_predictions(args.predictions, mode=args.mode)
        report = score_predictions(items, predictions, mode=args.mode)
        write_report(report, args.output)
        print(json.dumps({
            "mode": args.mode,
            "item_count": report["item_count"],
            "quality_gates_passed": report["quality_gates"]["passed"],
            "output": str(args.output),
        }, sort_keys=True))
        if args.enforce_gates and not report["quality_gates"]["passed"]:
            return 2
        return 0
    except BenchmarkValidationError as error:
        print(f"benchmark validation failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
