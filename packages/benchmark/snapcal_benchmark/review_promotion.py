from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable

from .models import (
    CLOUD_PROCESSORS,
    DIFFICULTIES,
    EXPECTED_AMBIGUITY_FIELDS,
    LANGUAGES,
    PROVENANCE_KINDS,
    SOURCE_CATEGORIES,
)
from .validation import (
    REPOSITORY_ROOT,
    BenchmarkValidationError,
    load_manifest,
    validate_corpus,
)


DECISIONS = frozenset({"pending", "reject", "approve"})
PROFILES = frozenset({"calibration", "acceptance"})


class ReviewPromotionError(ValueError):
    pass


def _read_jsonl(path: Path, label: str) -> list[dict[str, Any]]:
    if not path.is_file():
        raise ReviewPromotionError(f"{label} does not exist: {path}")
    rows: list[dict[str, Any]] = []
    for line_number, raw_line in enumerate(
        path.read_text(encoding="utf-8").splitlines(), start=1
    ):
        line = raw_line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError as error:
            raise ReviewPromotionError(
                f"{path}:{line_number}: invalid JSON: {error.msg}"
            ) from error
        if not isinstance(row, dict):
            raise ReviewPromotionError(f"{path}:{line_number}: row must be an object")
        rows.append(row)
    if not rows:
        raise ReviewPromotionError(f"{label} is empty: {path}")
    return rows


def _write_jsonl(path: Path, rows: Iterable[dict[str, Any]]) -> None:
    with path.open("w", encoding="utf-8") as output:
        for row in rows:
            output.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n")


def _path_is_within(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


def _require_external(path: Path, label: str) -> None:
    if _path_is_within(path.resolve(), REPOSITORY_ROOT):
        raise ReviewPromotionError(f"{label} must remain outside the repository")


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _candidate_id(image_sha256: str) -> str:
    return f"commons-{image_sha256[:16]}"


def _candidate_by_id(candidates_path: Path) -> dict[str, dict[str, Any]]:
    candidates = _read_jsonl(candidates_path, "candidate manifest")
    result: dict[str, dict[str, Any]] = {}
    hashes: set[str] = set()
    for row in candidates:
        digest = str(row.get("image_sha256", ""))
        if len(digest) != 64 or any(
            character not in "0123456789abcdef" for character in digest
        ):
            raise ReviewPromotionError(
                "candidate image_sha256 must be a lowercase SHA-256"
            )
        item_id = _candidate_id(digest)
        if item_id in result or digest in hashes:
            raise ReviewPromotionError("candidate image hashes must be unique")
        result[item_id] = row
        hashes.add(digest)
    return result


def _template_row(
    queue_row: dict[str, Any], candidate: dict[str, Any]
) -> dict[str, Any]:
    license_text = " ".join(
        value
        for value in (
            str(candidate.get("license_short_name", "")).strip(),
            str(candidate.get("license_url", "")).strip(),
        )
        if value
    )
    rights_holder = str(
        candidate.get("attribution") or candidate.get("artist") or ""
    ).strip()
    return {
        "schema_version": 1,
        "candidate_id": queue_row["candidate_id"],
        "image_sha256": candidate["image_sha256"],
        "decision": "pending",
        "language": "",
        "source_category": "",
        "difficulties": [],
        "captured_at": "",
        "timezone": "",
        "expected": {
            "title": "",
            "start": "",
            "end": None,
            "is_all_day": None,
            "location": None,
        },
        "expected_ambiguity_fields": [],
        "provenance": {
            "kind": "cc",
            "source": str(candidate.get("description_url", "")),
            "rights_holder": rights_holder,
            "license_or_permission": license_text,
            "redistributable": False,
        },
        "license_reviewed": False,
        "sanitized": False,
        "ground_truth_annotated": False,
        "benchmark_use_authorized": False,
        "cloud_processors": [],
        "authorization_reference": "",
        "primary_reviewer": "",
        "primary_reviewed_at": "",
        "critical_fields_second_reviewed": False,
        "second_reviewer": "",
        "second_reviewed_at": "",
        "machine_hints": {
            "language": queue_row.get("language_hint", "undetermined"),
            "source_category": queue_row.get("source_category_hint", "other"),
            "difficulties": queue_row.get("difficulty_hints", []),
            "likely_event_image": bool(queue_row.get("likely_event_image")),
        },
        "reviewer_notes": "",
    }


def create_review_template(
    candidates_path: Path,
    review_queue_path: Path,
    output_path: Path,
    *,
    likely_only: bool = False,
) -> dict[str, Any]:
    _require_external(candidates_path, "candidate manifest")
    _require_external(review_queue_path, "review queue")
    _require_external(output_path, "review template")
    if output_path.exists():
        raise ReviewPromotionError(
            "review template already exists; refusing to overwrite human work"
        )
    candidates = _candidate_by_id(candidates_path)
    queue = _read_jsonl(review_queue_path, "review queue")
    rows: list[dict[str, Any]] = []
    seen: set[str] = set()
    for queue_row in queue:
        item_id = str(queue_row.get("candidate_id", ""))
        if item_id in seen:
            raise ReviewPromotionError(f"duplicate review candidate: {item_id}")
        candidate = candidates.get(item_id)
        if candidate is None:
            raise ReviewPromotionError(
                f"review candidate is missing from intake: {item_id}"
            )
        if queue_row.get("image_sha256") != candidate.get("image_sha256"):
            raise ReviewPromotionError(f"review candidate hash mismatch: {item_id}")
        seen.add(item_id)
        if likely_only and not queue_row.get("likely_event_image"):
            continue
        rows.append(_template_row(queue_row, candidate))
    if not rows:
        raise ReviewPromotionError("review selection is empty")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    _write_jsonl(output_path, rows)
    return {
        "schema_version": 1,
        "item_count": len(rows),
        "approved_count": 0,
        "output": str(output_path),
        "notice": (
            "Machine hints are non-authoritative; all approval fields remain false."
        ),
    }


def _require_exact_keys(
    row: dict[str, Any], expected: set[str], item_id: str
) -> None:
    missing = sorted(expected - set(row))
    unknown = sorted(set(row) - expected)
    if missing or unknown:
        details: list[str] = []
        if missing:
            details.append("missing " + ", ".join(missing))
        if unknown:
            details.append("unknown " + ", ".join(unknown))
        raise ReviewPromotionError(f"{item_id}: {'; '.join(details)}")


def _require_true(value: Any, field: str, item_id: str) -> None:
    if value is not True:
        raise ReviewPromotionError(f"{item_id}: {field} must be explicitly true")


def _require_nonempty(value: Any, field: str, item_id: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ReviewPromotionError(f"{item_id}: {field} must be non-empty")
    return value.strip()


def _require_offset_datetime(value: Any, field: str, item_id: str) -> str:
    text = _require_nonempty(value, field, item_id)
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError as error:
        raise ReviewPromotionError(f"{item_id}: {field} must be ISO 8601") from error
    if parsed.tzinfo is None:
        raise ReviewPromotionError(
            f"{item_id}: {field} requires an explicit UTC offset"
        )
    return text


def _safe_source_image(
    candidates_path: Path, candidate: dict[str, Any], item_id: str
) -> Path:
    relative = Path(str(candidate.get("local_image", "")))
    if relative.is_absolute() or ".." in relative.parts:
        raise ReviewPromotionError(f"{item_id}: candidate image path is unsafe")
    root = candidates_path.resolve().parent
    image = (root / relative).resolve()
    if not _path_is_within(image, root) or not image.is_file():
        raise ReviewPromotionError(
            f"{item_id}: candidate image is missing or outside intake"
        )
    if _sha256(image) != candidate["image_sha256"]:
        raise ReviewPromotionError(f"{item_id}: candidate image SHA-256 mismatch")
    return image


def _approved_manifest_row(
    decision: dict[str, Any],
    candidate: dict[str, Any],
    image_name: str,
) -> dict[str, Any]:
    item_id = str(decision.get("candidate_id", "<unknown>"))
    _require_exact_keys(
        decision,
        {
            "schema_version",
            "candidate_id",
            "image_sha256",
            "decision",
            "language",
            "source_category",
            "difficulties",
            "captured_at",
            "timezone",
            "expected",
            "expected_ambiguity_fields",
            "provenance",
            "license_reviewed",
            "sanitized",
            "ground_truth_annotated",
            "benchmark_use_authorized",
            "cloud_processors",
            "authorization_reference",
            "primary_reviewer",
            "primary_reviewed_at",
            "critical_fields_second_reviewed",
            "second_reviewer",
            "second_reviewed_at",
            "machine_hints",
            "reviewer_notes",
        },
        item_id,
    )
    if decision.get("schema_version") != 1:
        raise ReviewPromotionError(f"{item_id}: unsupported review schema version")
    if decision.get("image_sha256") != candidate.get("image_sha256"):
        raise ReviewPromotionError(f"{item_id}: review decision hash mismatch")
    for field in (
        "license_reviewed",
        "sanitized",
        "ground_truth_annotated",
        "benchmark_use_authorized",
        "critical_fields_second_reviewed",
    ):
        _require_true(decision.get(field), field, item_id)
    if candidate.get("machine_license_allowlisted") is not True:
        raise ReviewPromotionError(
            f"{item_id}: source license was not machine allowlisted"
        )
    for field in ("license_reviewed", "sanitized", "cloud_processing_authorized"):
        if candidate.get(field) is not False:
            raise ReviewPromotionError(
                f"{item_id}: source intake approval flag {field} was modified"
            )

    language = _require_nonempty(decision.get("language"), "language", item_id)
    if language not in LANGUAGES:
        raise ReviewPromotionError(f"{item_id}: unsupported language")
    category = _require_nonempty(
        decision.get("source_category"), "source_category", item_id
    )
    if category not in SOURCE_CATEGORIES:
        raise ReviewPromotionError(f"{item_id}: unsupported source category")
    difficulties = decision.get("difficulties")
    if not isinstance(difficulties, list) or any(
        not isinstance(value, str) for value in difficulties
    ):
        raise ReviewPromotionError(f"{item_id}: difficulties must be a string array")
    unknown_difficulties = sorted(set(difficulties) - DIFFICULTIES)
    if unknown_difficulties:
        raise ReviewPromotionError(
            f"{item_id}: unsupported difficulties: {', '.join(unknown_difficulties)}"
        )
    ambiguities = decision.get("expected_ambiguity_fields")
    if not isinstance(ambiguities, list) or any(
        not isinstance(value, str) for value in ambiguities
    ):
        raise ReviewPromotionError(
            f"{item_id}: expected_ambiguity_fields must be a string array"
        )
    unknown_ambiguities = sorted(set(ambiguities) - EXPECTED_AMBIGUITY_FIELDS)
    if unknown_ambiguities:
        raise ReviewPromotionError(
            f"{item_id}: unsupported ambiguity fields: {', '.join(unknown_ambiguities)}"
        )

    cloud_processors = decision.get("cloud_processors")
    if not isinstance(cloud_processors, list) or any(
        not isinstance(value, str) for value in cloud_processors
    ):
        raise ReviewPromotionError(
            f"{item_id}: cloud_processors must be a string array"
        )
    unknown_processors = sorted(set(cloud_processors) - CLOUD_PROCESSORS)
    if unknown_processors:
        raise ReviewPromotionError(
            f"{item_id}: unsupported cloud processors: {', '.join(unknown_processors)}"
        )
    if "openrouter" not in cloud_processors:
        raise ReviewPromotionError(f"{item_id}: OpenRouter authorization is required")

    primary_reviewer = _require_nonempty(
        decision.get("primary_reviewer"), "primary_reviewer", item_id
    )
    second_reviewer = _require_nonempty(
        decision.get("second_reviewer"), "second_reviewer", item_id
    )
    if primary_reviewer.casefold() == second_reviewer.casefold():
        raise ReviewPromotionError(
            f"{item_id}: second reviewer must be independent"
        )
    _require_offset_datetime(
        decision.get("primary_reviewed_at"), "primary_reviewed_at", item_id
    )
    second_reviewed_at = _require_offset_datetime(
        decision.get("second_reviewed_at"), "second_reviewed_at", item_id
    )

    expected = decision.get("expected")
    if not isinstance(expected, dict):
        raise ReviewPromotionError(f"{item_id}: expected must be an object")
    provenance = decision.get("provenance")
    if not isinstance(provenance, dict):
        raise ReviewPromotionError(f"{item_id}: provenance must be an object")
    provenance_kind = provenance.get("kind")
    if provenance_kind not in PROVENANCE_KINDS - {"generated"}:
        raise ReviewPromotionError(
            f"{item_id}: invalid real-world provenance kind"
        )

    return {
        "schema_version": 2,
        "id": item_id,
        "image": f"images/{image_name}",
        "image_sha256": candidate["image_sha256"],
        "language": language,
        "source_category": category,
        "difficulties": difficulties,
        "captured_at": _require_nonempty(
            decision.get("captured_at"), "captured_at", item_id
        ),
        "timezone": _require_nonempty(
            decision.get("timezone"), "timezone", item_id
        ),
        "expected": expected,
        "expected_ambiguity_fields": ambiguities,
        "provenance": provenance,
        "sanitized": True,
        "synthetic": False,
        "processing_authorization": {
            "benchmark_use": True,
            "cloud_processors": cloud_processors,
            "authorization_reference": _require_nonempty(
                decision.get("authorization_reference"),
                "authorization_reference",
                item_id,
            ),
        },
        "annotation": {
            "critical_fields_second_reviewed": True,
            "reviewed_at": second_reviewed_at,
        },
    }


def promote_reviews(
    candidates_path: Path,
    decisions_path: Path,
    output_dir: Path,
    *,
    profile: str,
) -> dict[str, Any]:
    if profile not in PROFILES:
        raise ReviewPromotionError(f"unsupported promotion profile: {profile}")
    for path, label in (
        (candidates_path, "candidate manifest"),
        (decisions_path, "review decisions"),
        (output_dir, "private corpus output"),
    ):
        _require_external(path, label)
    if output_dir.exists():
        raise ReviewPromotionError(
            "output directory already exists; refusing to overwrite it"
        )

    candidates = _candidate_by_id(candidates_path)
    decisions = _read_jsonl(decisions_path, "review decisions")
    approved: list[tuple[dict[str, Any], dict[str, Any], Path]] = []
    seen: set[str] = set()
    for decision in decisions:
        item_id = str(decision.get("candidate_id", ""))
        if item_id in seen:
            raise ReviewPromotionError(f"duplicate review decision: {item_id}")
        seen.add(item_id)
        candidate = candidates.get(item_id)
        if candidate is None:
            raise ReviewPromotionError(f"unknown review candidate: {item_id}")
        outcome = decision.get("decision")
        if outcome not in DECISIONS:
            raise ReviewPromotionError(f"{item_id}: unsupported review decision")
        if outcome != "approve":
            continue
        source_image = _safe_source_image(candidates_path, candidate, item_id)
        approved.append((decision, candidate, source_image))
    if not approved:
        raise ReviewPromotionError("no explicitly approved candidates were provided")

    output_dir.parent.mkdir(parents=True, exist_ok=True)
    staging = output_dir.parent / f".{output_dir.name}.staging-{uuid.uuid4().hex}"
    images_dir = staging / "images"
    images_dir.mkdir(parents=True)
    try:
        manifest_rows: list[dict[str, Any]] = []
        for decision, candidate, source_image in approved:
            item_id = str(decision["candidate_id"])
            suffix = source_image.suffix.lower() or ".img"
            image_name = f"{item_id}{suffix}"
            destination = images_dir / image_name
            shutil.copy2(source_image, destination)
            if _sha256(destination) != candidate["image_sha256"]:
                raise ReviewPromotionError(
                    f"{item_id}: copied image SHA-256 mismatch"
                )
            manifest_rows.append(
                _approved_manifest_row(decision, candidate, image_name)
            )

        manifest_path = staging / "manifest.jsonl"
        _write_jsonl(manifest_path, manifest_rows)
        items = load_manifest(manifest_path)
        summary = validate_corpus(
            items,
            manifest_path=manifest_path,
            require_complete=profile == "acceptance",
            require_calibration=profile == "calibration",
            require_real_world=True,
            require_cloud_authorized="openrouter",
            require_second_reviewed=True,
        )
        promotion_summary = {
            "schema_version": 1,
            "profile": profile,
            "item_count": len(items),
            "manifest_sha256": _sha256(manifest_path),
            "candidate_manifest_sha256": _sha256(candidates_path),
            "review_decisions_sha256": _sha256(decisions_path),
            "validation": summary.as_dict(),
            "notice": (
                "Private item-level review records remain external and were not copied into Git."
            ),
        }
        (staging / "promotion-summary.json").write_text(
            json.dumps(
                promotion_summary, ensure_ascii=False, indent=2, sort_keys=True
            )
            + "\n",
            encoding="utf-8",
        )
        staging.rename(output_dir)
        return promotion_summary
    except Exception:
        shutil.rmtree(staging, ignore_errors=True)
        raise


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Prepare human review records and promote only fully approved "
            "private benchmark items."
        )
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    template = subparsers.add_parser("template")
    template.add_argument("--candidates", type=Path, required=True)
    template.add_argument("--review-queue", type=Path, required=True)
    template.add_argument("--output", type=Path, required=True)
    template.add_argument("--likely-only", action="store_true")

    promote = subparsers.add_parser("promote")
    promote.add_argument("--candidates", type=Path, required=True)
    promote.add_argument("--decisions", type=Path, required=True)
    promote.add_argument("--output-dir", type=Path, required=True)
    promote.add_argument("--profile", choices=sorted(PROFILES), required=True)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.command == "template":
            summary = create_review_template(
                args.candidates,
                args.review_queue,
                args.output,
                likely_only=args.likely_only,
            )
        else:
            summary = promote_reviews(
                args.candidates,
                args.decisions,
                args.output_dir,
                profile=args.profile,
            )
    except (OSError, ReviewPromotionError, BenchmarkValidationError) as error:
        print(f"benchmark review promotion failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(summary, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
