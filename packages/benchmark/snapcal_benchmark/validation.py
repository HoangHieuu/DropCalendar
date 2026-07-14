from __future__ import annotations

import hashlib
import json
import re
from datetime import date, datetime
from pathlib import Path
from typing import Any, Iterable
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from .models import (
    DIFFICULTIES,
    FAILURE_REASONS,
    LANGUAGES,
    MODES,
    OUTCOMES,
    PROVENANCE_KINDS,
    SCHEMA_VERSION,
    SOURCE_CATEGORIES,
    BenchmarkItem,
    BenchmarkPrediction,
    ExpectedEvent,
    Provenance,
    ValidationSummary,
)


ITEM_ID_PATTERN = re.compile(r"^[a-z0-9][a-z0-9_-]{2,63}$")
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
CHALLENGING_LABELS = frozenset({"noisy", "low_resolution", "decorative_font"})
CRITICAL_EVIDENCE_FIELDS = frozenset({"title", "start", "location"})


class BenchmarkValidationError(ValueError):
    """Raised when benchmark input violates a fail-closed contract."""


def load_manifest(path: Path) -> list[BenchmarkItem]:
    rows = _read_jsonl(path)
    items = [_parse_item(row, line_number) for line_number, row in rows]
    _reject_duplicate_ids((item.item_id for item in items), "manifest")
    return items


def load_predictions(path: Path, *, mode: str | None = None) -> list[BenchmarkPrediction]:
    if mode is not None and mode not in MODES:
        raise BenchmarkValidationError(f"unsupported prediction mode: {mode}")
    rows = _read_jsonl(path)
    predictions = [_parse_prediction(row, line_number) for line_number, row in rows]
    if mode is not None:
        predictions = [prediction for prediction in predictions if prediction.mode == mode]
    _reject_duplicate_ids(
        (f"{prediction.mode}:{prediction.item_id}" for prediction in predictions),
        "predictions",
    )
    return predictions


def validate_corpus(
    items: list[BenchmarkItem],
    *,
    manifest_path: Path,
    require_complete: bool = False,
    require_real_world: bool = False,
) -> ValidationSummary:
    corpus_root = manifest_path.resolve().parent
    for item in items:
        image_path = _safe_image_path(corpus_root, item.image, item.item_id)
        if not image_path.is_file():
            raise BenchmarkValidationError(
                f"{item.item_id}: referenced image does not exist: {item.image}"
            )
        _validate_supported_image_header(image_path, item.item_id)
        digest = _sha256(image_path)
        if digest != item.image_sha256:
            raise BenchmarkValidationError(f"{item.item_id}: image SHA-256 mismatch")

    vietnamese_or_mixed = sum(item.language in {"vietnamese", "mixed"} for item in items)
    english = sum(item.language == "english" for item in items)
    challenging = sum(bool(set(item.difficulties) & CHALLENGING_LABELS) for item in items)
    synthetic = sum(item.synthetic for item in items)
    categories = tuple(sorted({item.source_category for item in items}))

    if require_complete:
        failures: list[str] = []
        if len(items) < 100:
            failures.append(f"requires at least 100 items, found {len(items)}")
        if vietnamese_or_mixed < 50:
            failures.append(
                "requires at least 50 Vietnamese or mixed-language items, "
                f"found {vietnamese_or_mixed}"
            )
        if english < 30:
            failures.append(f"requires at least 30 English items, found {english}")
        if challenging < 20:
            failures.append(
                "requires at least 20 noisy, low-resolution, or decorative-font items, "
                f"found {challenging}"
            )
        missing_categories = sorted(SOURCE_CATEGORIES - set(categories))
        if missing_categories:
            failures.append(
                "missing required source categories: " + ", ".join(missing_categories)
            )
        if failures:
            raise BenchmarkValidationError("incomplete benchmark corpus: " + "; ".join(failures))

    if require_real_world and synthetic:
        raise BenchmarkValidationError(
            "real-world benchmark corpus must contain zero synthetic items, "
            f"found {synthetic}"
        )

    return ValidationSummary(
        total=len(items),
        vietnamese_or_mixed=vietnamese_or_mixed,
        english=english,
        challenging=challenging,
        synthetic=synthetic,
        non_synthetic=len(items) - synthetic,
        source_categories=categories,
    )


def validate_prediction_coverage(
    items: list[BenchmarkItem],
    predictions: list[BenchmarkPrediction],
    *,
    mode: str,
) -> None:
    if mode not in MODES:
        raise BenchmarkValidationError(f"unsupported prediction mode: {mode}")
    item_ids = {item.item_id for item in items}
    prediction_ids = {
        prediction.item_id for prediction in predictions if prediction.mode == mode
    }
    unknown = sorted(prediction_ids - item_ids)
    missing = sorted(item_ids - prediction_ids)
    if unknown:
        raise BenchmarkValidationError("predictions contain unknown item IDs: " + ", ".join(unknown))
    if missing:
        raise BenchmarkValidationError("predictions are missing item IDs: " + ", ".join(missing))


def _read_jsonl(path: Path) -> list[tuple[int, dict[str, Any]]]:
    if not path.is_file():
        raise BenchmarkValidationError(f"JSON Lines file does not exist: {path}")
    rows: list[tuple[int, dict[str, Any]]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line_number, raw_line in enumerate(handle, start=1):
            line = raw_line.strip()
            if not line:
                continue
            try:
                value = json.loads(line)
            except json.JSONDecodeError as error:
                raise BenchmarkValidationError(
                    f"{path}:{line_number}: invalid JSON: {error.msg}"
                ) from error
            if not isinstance(value, dict):
                raise BenchmarkValidationError(
                    f"{path}:{line_number}: each row must be a JSON object"
                )
            rows.append((line_number, value))
    if not rows:
        raise BenchmarkValidationError(f"JSON Lines file is empty: {path}")
    return rows


def _parse_item(row: dict[str, Any], line_number: int) -> BenchmarkItem:
    prefix = f"manifest line {line_number}"
    _require_exact_keys(
        row,
        {
            "schema_version",
            "id",
            "image",
            "image_sha256",
            "language",
            "source_category",
            "difficulties",
            "captured_at",
            "timezone",
            "expected",
            "provenance",
            "sanitized",
            "synthetic",
        },
        prefix,
    )
    _require_schema_version(row["schema_version"], prefix)
    item_id = _require_string(row["id"], f"{prefix}.id")
    if not ITEM_ID_PATTERN.fullmatch(item_id):
        raise BenchmarkValidationError(f"{prefix}.id: invalid stable identifier")
    image = _require_string(row["image"], f"{prefix}.image")
    image_sha256 = _require_string(row["image_sha256"], f"{prefix}.image_sha256")
    if not SHA256_PATTERN.fullmatch(image_sha256):
        raise BenchmarkValidationError(f"{prefix}.image_sha256: expected lowercase SHA-256")
    language = _require_choice(row["language"], LANGUAGES, f"{prefix}.language")
    source_category = _require_choice(
        row["source_category"], SOURCE_CATEGORIES, f"{prefix}.source_category"
    )
    difficulties = _require_string_list(row["difficulties"], f"{prefix}.difficulties")
    unknown_difficulties = sorted(set(difficulties) - DIFFICULTIES)
    if unknown_difficulties:
        raise BenchmarkValidationError(
            f"{prefix}.difficulties: unsupported values: {', '.join(unknown_difficulties)}"
        )
    captured_at = _require_string(row["captured_at"], f"{prefix}.captured_at")
    captured_datetime = _parse_datetime(captured_at, f"{prefix}.captured_at")
    if captured_datetime.tzinfo is None:
        raise BenchmarkValidationError(f"{prefix}.captured_at: explicit UTC offset required")
    timezone = _require_string(row["timezone"], f"{prefix}.timezone")
    _parse_timezone(timezone, f"{prefix}.timezone")
    expected = _parse_expected(row["expected"], f"{prefix}.expected")
    provenance = _parse_provenance(row["provenance"], f"{prefix}.provenance")
    sanitized = _require_bool(row["sanitized"], f"{prefix}.sanitized")
    synthetic = _require_bool(row["synthetic"], f"{prefix}.synthetic")
    if not sanitized:
        raise BenchmarkValidationError(f"{prefix}.sanitized: must be true")
    if not provenance.redistributable:
        raise BenchmarkValidationError(f"{prefix}.provenance.redistributable: must be true")
    if synthetic and provenance.kind != "generated":
        raise BenchmarkValidationError(
            f"{prefix}: synthetic items must use generated provenance"
        )
    if not synthetic and provenance.kind == "generated":
        raise BenchmarkValidationError(
            f"{prefix}: generated provenance requires synthetic=true"
        )
    return BenchmarkItem(
        schema_version=SCHEMA_VERSION,
        item_id=item_id,
        image=image,
        image_sha256=image_sha256,
        language=language,
        source_category=source_category,
        difficulties=difficulties,
        captured_at=captured_at,
        timezone=timezone,
        expected=expected,
        provenance=provenance,
        sanitized=sanitized,
        synthetic=synthetic,
    )


def _parse_expected(value: Any, prefix: str) -> ExpectedEvent:
    row = _require_object(value, prefix)
    _require_exact_keys(row, {"title", "start", "end", "is_all_day", "location"}, prefix)
    title = _require_string(row["title"], f"{prefix}.title")
    is_all_day = _require_bool(row["is_all_day"], f"{prefix}.is_all_day")
    start = _require_string(row["start"], f"{prefix}.start")
    end = _optional_string(row["end"], f"{prefix}.end")
    location = _optional_string(row["location"], f"{prefix}.location")
    if is_all_day:
        _parse_date(start, f"{prefix}.start")
        if end is not None:
            _parse_date(end, f"{prefix}.end")
    else:
        parsed_start = _parse_datetime(start, f"{prefix}.start")
        if parsed_start.tzinfo is None:
            raise BenchmarkValidationError(f"{prefix}.start: explicit UTC offset required")
        if end is not None:
            parsed_end = _parse_datetime(end, f"{prefix}.end")
            if parsed_end.tzinfo is None:
                raise BenchmarkValidationError(f"{prefix}.end: explicit UTC offset required")
    return ExpectedEvent(
        title=title,
        start=start,
        end=end,
        is_all_day=is_all_day,
        location=location,
    )


def _parse_provenance(value: Any, prefix: str) -> Provenance:
    row = _require_object(value, prefix)
    _require_exact_keys(
        row,
        {"kind", "source", "rights_holder", "license_or_permission", "redistributable"},
        prefix,
    )
    return Provenance(
        kind=_require_choice(row["kind"], PROVENANCE_KINDS, f"{prefix}.kind"),
        source=_require_string(row["source"], f"{prefix}.source"),
        rights_holder=_require_string(row["rights_holder"], f"{prefix}.rights_holder"),
        license_or_permission=_require_string(
            row["license_or_permission"], f"{prefix}.license_or_permission"
        ),
        redistributable=_require_bool(
            row["redistributable"], f"{prefix}.redistributable"
        ),
    )


def _parse_prediction(row: dict[str, Any], line_number: int) -> BenchmarkPrediction:
    prefix = f"prediction line {line_number}"
    _require_exact_keys(
        row,
        {
            "schema_version",
            "item_id",
            "mode",
            "outcome",
            "title",
            "start",
            "end",
            "is_all_day",
            "location",
            "evidence_fields",
            "ambiguity_fields",
            "latency_ms",
            "failure_reason",
        },
        prefix,
    )
    _require_schema_version(row["schema_version"], prefix)
    item_id = _require_string(row["item_id"], f"{prefix}.item_id")
    mode = _require_choice(row["mode"], MODES, f"{prefix}.mode")
    outcome = _require_choice(row["outcome"], OUTCOMES, f"{prefix}.outcome")
    title = _optional_string(row["title"], f"{prefix}.title")
    start = _optional_string(row["start"], f"{prefix}.start")
    end = _optional_string(row["end"], f"{prefix}.end")
    is_all_day = row["is_all_day"]
    if is_all_day is not None:
        is_all_day = _require_bool(is_all_day, f"{prefix}.is_all_day")
    location = _optional_string(row["location"], f"{prefix}.location")
    evidence_fields = _require_string_list(row["evidence_fields"], f"{prefix}.evidence_fields")
    ambiguity_fields = _require_string_list(
        row["ambiguity_fields"], f"{prefix}.ambiguity_fields"
    )
    latency_ms = _require_number(row["latency_ms"], f"{prefix}.latency_ms")
    if latency_ms < 0:
        raise BenchmarkValidationError(f"{prefix}.latency_ms: must be non-negative")
    failure_reason = _optional_string(row["failure_reason"], f"{prefix}.failure_reason")
    if outcome == "failure":
        if failure_reason not in FAILURE_REASONS:
            raise BenchmarkValidationError(
                f"{prefix}.failure_reason: structured failure reason required"
            )
        if any(value is not None for value in (title, start, end, is_all_day, location)):
            raise BenchmarkValidationError(
                f"{prefix}: failure predictions must not contain proposed event fields"
            )
    else:
        if failure_reason is not None:
            raise BenchmarkValidationError(
                f"{prefix}.failure_reason: draft predictions cannot include a failure reason"
            )
        if is_all_day is None:
            raise BenchmarkValidationError(f"{prefix}.is_all_day: required for draft outcome")
        if start is not None:
            if is_all_day:
                _parse_date(start, f"{prefix}.start")
            else:
                parsed_start = _parse_datetime(start, f"{prefix}.start")
                if parsed_start.tzinfo is None:
                    raise BenchmarkValidationError(
                        f"{prefix}.start: explicit UTC offset required"
                    )
    unknown_evidence = sorted(set(evidence_fields) - CRITICAL_EVIDENCE_FIELDS)
    if unknown_evidence:
        raise BenchmarkValidationError(
            f"{prefix}.evidence_fields: unsupported values: {', '.join(unknown_evidence)}"
        )
    return BenchmarkPrediction(
        schema_version=SCHEMA_VERSION,
        item_id=item_id,
        mode=mode,
        outcome=outcome,
        title=title,
        start=start,
        end=end,
        is_all_day=is_all_day,
        location=location,
        evidence_fields=evidence_fields,
        ambiguity_fields=ambiguity_fields,
        latency_ms=latency_ms,
        failure_reason=failure_reason,
    )


def _safe_image_path(root: Path, relative: str, item_id: str) -> Path:
    candidate = Path(relative)
    if candidate.is_absolute() or ".." in candidate.parts:
        raise BenchmarkValidationError(f"{item_id}: image path must stay inside corpus")
    resolved = (root / candidate).resolve()
    try:
        resolved.relative_to(root)
    except ValueError as error:
        raise BenchmarkValidationError(f"{item_id}: image path escapes corpus") from error
    return resolved


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _validate_supported_image_header(path: Path, item_id: str) -> None:
    with path.open("rb") as handle:
        header = handle.read(32)
    is_png = header.startswith(b"\x89PNG\r\n\x1a\n")
    is_jpeg = header.startswith(b"\xff\xd8\xff")
    is_heic = len(header) >= 12 and header[4:8] == b"ftyp" and header[8:12] in {
        b"heic",
        b"heix",
        b"hevc",
        b"hevx",
        b"mif1",
        b"msf1",
    }
    if not (is_png or is_jpeg or is_heic):
        raise BenchmarkValidationError(
            f"{item_id}: image content is not PNG, JPEG, or HEIC"
        )


def _reject_duplicate_ids(values: Iterable[str], label: str) -> None:
    seen: set[str] = set()
    duplicates: set[str] = set()
    for value in values:
        if value in seen:
            duplicates.add(value)
        seen.add(value)
    if duplicates:
        raise BenchmarkValidationError(
            f"duplicate {label} identifiers: {', '.join(sorted(duplicates))}"
        )


def _require_exact_keys(row: dict[str, Any], expected: set[str], prefix: str) -> None:
    missing = sorted(expected - set(row))
    unknown = sorted(set(row) - expected)
    if missing or unknown:
        parts = []
        if missing:
            parts.append("missing " + ", ".join(missing))
        if unknown:
            parts.append("unknown " + ", ".join(unknown))
        raise BenchmarkValidationError(f"{prefix}: {'; '.join(parts)}")


def _require_schema_version(value: Any, prefix: str) -> None:
    if value != SCHEMA_VERSION:
        raise BenchmarkValidationError(
            f"{prefix}.schema_version: expected {SCHEMA_VERSION}"
        )


def _require_object(value: Any, prefix: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise BenchmarkValidationError(f"{prefix}: expected object")
    return value


def _require_string(value: Any, prefix: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise BenchmarkValidationError(f"{prefix}: expected non-empty string")
    return value.strip()


def _optional_string(value: Any, prefix: str) -> str | None:
    if value is None:
        return None
    return _require_string(value, prefix)


def _require_bool(value: Any, prefix: str) -> bool:
    if not isinstance(value, bool):
        raise BenchmarkValidationError(f"{prefix}: expected boolean")
    return value


def _require_number(value: Any, prefix: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise BenchmarkValidationError(f"{prefix}: expected number")
    return float(value)


def _require_choice(value: Any, choices: frozenset[str], prefix: str) -> str:
    choice = _require_string(value, prefix)
    if choice not in choices:
        raise BenchmarkValidationError(
            f"{prefix}: expected one of {', '.join(sorted(choices))}"
        )
    return choice


def _require_string_list(value: Any, prefix: str) -> tuple[str, ...]:
    if not isinstance(value, list):
        raise BenchmarkValidationError(f"{prefix}: expected array")
    result = tuple(_require_string(item, f"{prefix}[]") for item in value)
    if len(set(result)) != len(result):
        raise BenchmarkValidationError(f"{prefix}: duplicate values are not allowed")
    return result


def _parse_datetime(value: str, prefix: str) -> datetime:
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise BenchmarkValidationError(f"{prefix}: invalid RFC 3339 datetime") from error


def _parse_date(value: str, prefix: str) -> date:
    try:
        return date.fromisoformat(value)
    except ValueError as error:
        raise BenchmarkValidationError(f"{prefix}: invalid YYYY-MM-DD date") from error


def _parse_timezone(value: str, prefix: str) -> ZoneInfo:
    try:
        return ZoneInfo(value)
    except ZoneInfoNotFoundError as error:
        raise BenchmarkValidationError(f"{prefix}: unknown IANA timezone") from error
