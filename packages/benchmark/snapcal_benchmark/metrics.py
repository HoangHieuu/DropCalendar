from __future__ import annotations

import json
import statistics
import unicodedata
from collections import Counter
from datetime import date, datetime
from pathlib import Path
from typing import Any, Callable
from zoneinfo import ZoneInfo

from .models import BenchmarkItem, BenchmarkPrediction, SCHEMA_VERSION
from .validation import BenchmarkValidationError, validate_prediction_coverage


QUALITY_TARGETS = {
    "vietnamese_or_mixed": {"title_accuracy": 0.85, "date_accuracy": 0.85, "time_accuracy": 0.80},
    "english": {"title_accuracy": 0.90, "date_accuracy": 0.90, "time_accuracy": 0.85},
}
CRITICAL_WRONG_RATE_MAX = 0.03
MEDIAN_LATENCY_MS_MAX = 10_000.0
PREDICTION_AMBIGUITY_TO_MANIFEST = {
    "title": "title",
    "dateTime": "start",
    "endTime": "end",
    "location": "location",
    "extraction": "extraction",
}


def score_predictions(
    items: list[BenchmarkItem],
    predictions: list[BenchmarkPrediction],
    *,
    mode: str,
) -> dict[str, Any]:
    validate_prediction_coverage(items, predictions, mode=mode)
    prediction_by_id = {
        prediction.item_id: prediction
        for prediction in predictions
        if prediction.mode == mode
    }
    cohorts: dict[str, list[BenchmarkItem]] = {
        "all": items,
        "vietnamese": [item for item in items if item.language == "vietnamese"],
        "english": [item for item in items if item.language == "english"],
        "mixed": [item for item in items if item.language == "mixed"],
        "vietnamese_or_mixed": [
            item for item in items if item.language in {"vietnamese", "mixed"}
        ],
    }
    metrics = {
        cohort: _score_cohort(cohort_items, prediction_by_id)
        for cohort, cohort_items in cohorts.items()
    }
    gates = _quality_gates(metrics, mode=mode)
    failures = []
    for item in items:
        prediction = prediction_by_id[item.item_id]
        mismatches = _mismatch_fields(item, prediction)
        expected_ambiguities = set(item.expected_ambiguity_fields)
        predicted_ambiguities = _normalized_ambiguity_fields(prediction)
        missed_ambiguities = sorted(expected_ambiguities - predicted_ambiguities)
        unexpected_ambiguities = sorted(predicted_ambiguities - expected_ambiguities)
        if prediction.outcome == "failure" or mismatches or missed_ambiguities:
            failures.append({
                "item_id": item.item_id,
                "language": item.language,
                "source_category": item.source_category,
                "difficulties": list(item.difficulties),
                "failure_reason": prediction.failure_reason,
                "mismatch_fields": mismatches,
                "missed_ambiguity_fields": missed_ambiguities,
                "unexpected_ambiguity_fields": unexpected_ambiguities,
                "latency_ms": prediction.latency_ms,
            })
    synthetic_count = sum(item.synthetic for item in items)
    if synthetic_count == len(items):
        claim_scope = "synthetic_regression_only"
    elif synthetic_count == 0:
        claim_scope = "licensed_real_world_corpus"
    else:
        claim_scope = "mixed_synthetic_and_real_world"
    return {
        "schema_version": SCHEMA_VERSION,
        "mode": mode,
        "item_count": len(items),
        "claim_scope": claim_scope,
        "corpus_composition": {
            "synthetic": synthetic_count,
            "non_synthetic": len(items) - synthetic_count,
        },
        "metrics": metrics,
        "failure_counts": _failure_counts(items, prediction_by_id),
        "quality_gates": gates,
        "failures": failures,
        "privacy": {
            "contains_image_bytes": False,
            "contains_raw_ocr": False,
            "contains_event_values": False,
        },
    }


def write_report(report: dict[str, Any], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def _score_cohort(
    items: list[BenchmarkItem],
    prediction_by_id: dict[str, BenchmarkPrediction],
) -> dict[str, Any]:
    if not items:
        return {
            "count": 0,
            "title_accuracy": None,
            "date_accuracy": None,
            "time_accuracy": None,
            "location_accuracy": None,
            "critical_wrong_rate": None,
            "structured_failure_rate": None,
            "critical_evidence_coverage": None,
            "median_latency_ms": None,
            "p90_latency_ms": None,
            "p95_latency_ms": None,
            "critical_missing_count": 0,
            "critical_wrong_count": 0,
            "date_missing_count": 0,
            "date_wrong_count": 0,
            "time_missing_count": 0,
            "time_wrong_count": 0,
            "ambiguity_expected_field_count": 0,
            "ambiguity_predicted_field_count": 0,
            "ambiguity_true_positive_field_count": 0,
            "ambiguity_missed_field_count": 0,
            "ambiguity_unexpected_field_count": 0,
            "ambiguity_precision": None,
            "ambiguity_recall": None,
            "ambiguity_exact_item_rate": None,
        }

    title_correct = 0
    date_correct = 0
    timed_items = 0
    time_correct = 0
    location_items = 0
    location_correct = 0
    wrong_critical = 0
    missing_critical = 0
    date_missing = 0
    date_wrong = 0
    time_missing = 0
    time_wrong = 0
    critical_denominator = 0
    critical_evidence_present = 0
    critical_evidence_denominator = 0
    structured_failures = 0
    latencies: list[float] = []
    ambiguity_expected_fields = 0
    ambiguity_predicted_fields = 0
    ambiguity_true_positive_fields = 0
    ambiguity_missed_fields = 0
    ambiguity_unexpected_fields = 0
    ambiguity_exact_items = 0

    for item in items:
        prediction = prediction_by_id[item.item_id]
        latencies.append(prediction.latency_ms)
        if prediction.outcome == "failure":
            structured_failures += 1
        title_correct += _text_equal(item.expected.title, prediction.title)
        expected_date, predicted_date = _date_values(item, prediction)
        date_correct += expected_date == predicted_date
        critical_denominator += 1
        if predicted_date is None:
            missing_critical += 1
            date_missing += 1
        elif predicted_date != expected_date:
            wrong_critical += 1
            date_wrong += 1
        if not item.expected.is_all_day:
            timed_items += 1
            expected_time, predicted_time = _time_values(item, prediction)
            time_correct += expected_time == predicted_time
            critical_denominator += 1
            if predicted_time is None:
                missing_critical += 1
                time_missing += 1
            elif predicted_time != expected_time:
                wrong_critical += 1
                time_wrong += 1
        if item.expected.location is not None:
            location_items += 1
            location_correct += _text_equal(item.expected.location, prediction.location)
        expected_evidence = ["title", "start"]
        if item.expected.location is not None:
            expected_evidence.append("location")
        critical_evidence_denominator += len(expected_evidence)
        critical_evidence_present += len(set(expected_evidence) & set(prediction.evidence_fields))

        expected_ambiguities = set(item.expected_ambiguity_fields)
        predicted_ambiguities = _normalized_ambiguity_fields(prediction)
        true_positive_ambiguities = expected_ambiguities & predicted_ambiguities
        ambiguity_expected_fields += len(expected_ambiguities)
        ambiguity_predicted_fields += len(predicted_ambiguities)
        ambiguity_true_positive_fields += len(true_positive_ambiguities)
        ambiguity_missed_fields += len(expected_ambiguities - predicted_ambiguities)
        ambiguity_unexpected_fields += len(predicted_ambiguities - expected_ambiguities)
        ambiguity_exact_items += expected_ambiguities == predicted_ambiguities

    count = len(items)
    return {
        "count": count,
        "title_accuracy": title_correct / count,
        "date_accuracy": date_correct / count,
        "time_accuracy": time_correct / timed_items if timed_items else None,
        "location_accuracy": location_correct / location_items if location_items else None,
        "critical_wrong_rate": wrong_critical / critical_denominator,
        "critical_missing_count": missing_critical,
        "critical_wrong_count": wrong_critical,
        "date_missing_count": date_missing,
        "date_wrong_count": date_wrong,
        "time_missing_count": time_missing,
        "time_wrong_count": time_wrong,
        "structured_failure_rate": structured_failures / count,
        "critical_evidence_coverage": (
            critical_evidence_present / critical_evidence_denominator
            if critical_evidence_denominator
            else None
        ),
        "median_latency_ms": statistics.median(latencies),
        "p90_latency_ms": _percentile(latencies, 0.90),
        "p95_latency_ms": _percentile(latencies, 0.95),
        "ambiguity_expected_field_count": ambiguity_expected_fields,
        "ambiguity_predicted_field_count": ambiguity_predicted_fields,
        "ambiguity_true_positive_field_count": ambiguity_true_positive_fields,
        "ambiguity_missed_field_count": ambiguity_missed_fields,
        "ambiguity_unexpected_field_count": ambiguity_unexpected_fields,
        "ambiguity_precision": (
            ambiguity_true_positive_fields / ambiguity_predicted_fields
            if ambiguity_predicted_fields
            else None
        ),
        "ambiguity_recall": (
            ambiguity_true_positive_fields / ambiguity_expected_fields
            if ambiguity_expected_fields
            else None
        ),
        "ambiguity_exact_item_rate": ambiguity_exact_items / count,
    }


def _quality_gates(metrics: dict[str, dict[str, Any]], *, mode: str) -> dict[str, Any]:
    checks: dict[str, bool | None] = {}
    if mode == "accuracy":
        for cohort, targets in QUALITY_TARGETS.items():
            cohort_metrics = metrics[cohort]
            for metric, target in targets.items():
                value = cohort_metrics[metric]
                checks[f"{cohort}.{metric}"] = None if value is None else value >= target
    all_metrics = metrics["all"]
    wrong_rate = all_metrics["critical_wrong_rate"]
    latency = all_metrics["median_latency_ms"]
    checks["all.critical_wrong_rate"] = (
        None if wrong_rate is None else wrong_rate <= CRITICAL_WRONG_RATE_MAX
    )
    checks["all.median_latency_ms"] = (
        None if latency is None else latency <= MEDIAN_LATENCY_MS_MAX
    )
    evidence_coverage = all_metrics["critical_evidence_coverage"]
    checks["all.critical_evidence_coverage"] = (
        None if evidence_coverage is None else evidence_coverage == 1.0
    )
    evaluated = [value for value in checks.values() if value is not None]
    return {
        "profile": mode,
        "passed": bool(evaluated) and all(evaluated),
        "checks": checks,
    }


def _normalized_ambiguity_fields(prediction: BenchmarkPrediction) -> set[str]:
    return {
        PREDICTION_AMBIGUITY_TO_MANIFEST.get(field, field)
        for field in prediction.ambiguity_fields
    }


def _percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    position = (len(ordered) - 1) * fraction
    lower_index = int(position)
    upper_index = min(lower_index + 1, len(ordered) - 1)
    interpolation = position - lower_index
    return ordered[lower_index] + (
        ordered[upper_index] - ordered[lower_index]
    ) * interpolation


def _failure_counts(
    items: list[BenchmarkItem],
    prediction_by_id: dict[str, BenchmarkPrediction],
) -> dict[str, Any]:
    by_language: Counter[str] = Counter()
    by_source_category: Counter[str] = Counter()
    by_difficulty: Counter[str] = Counter()
    by_reason: Counter[str] = Counter()
    structured_total = 0
    problem_total = 0

    for item in items:
        prediction = prediction_by_id[item.item_id]
        mismatches = _mismatch_fields(item, prediction)
        missed_ambiguities = (
            set(item.expected_ambiguity_fields) - _normalized_ambiguity_fields(prediction)
        )
        is_problem = prediction.outcome == "failure" or bool(mismatches) or bool(missed_ambiguities)
        if not is_problem:
            continue

        problem_total += 1
        by_language[item.language] += 1
        by_source_category[item.source_category] += 1
        for difficulty in item.difficulties:
            by_difficulty[difficulty] += 1
        if prediction.outcome == "failure":
            structured_total += 1
            by_reason[prediction.failure_reason or "unspecified_failure"] += 1
        if mismatches:
            by_reason["field_mismatch"] += 1
        if missed_ambiguities:
            by_reason["missed_expected_ambiguity"] += 1

    return {
        "problem_item_count": problem_total,
        "structured_failure_count": structured_total,
        "problem_by_language": dict(sorted(by_language.items())),
        "problem_by_source_category": dict(sorted(by_source_category.items())),
        "problem_by_difficulty": dict(sorted(by_difficulty.items())),
        "problem_by_reason": dict(sorted(by_reason.items())),
    }


def _mismatch_fields(item: BenchmarkItem, prediction: BenchmarkPrediction) -> list[str]:
    if prediction.outcome == "failure":
        return []
    mismatches: list[str] = []
    if not _text_equal(item.expected.title, prediction.title):
        mismatches.append("title")
    expected_date, predicted_date = _date_values(item, prediction)
    if expected_date != predicted_date:
        mismatches.append("date")
    if not item.expected.is_all_day:
        expected_time, predicted_time = _time_values(item, prediction)
        if expected_time != predicted_time:
            mismatches.append("time")
    if item.expected.location is not None and not _text_equal(
        item.expected.location, prediction.location
    ):
        mismatches.append("location")
    if prediction.is_all_day != item.expected.is_all_day:
        mismatches.append("all_day")
    return mismatches


def _text_equal(expected: str, actual: str | None) -> bool:
    if actual is None:
        return False
    return _normalize_text(expected) == _normalize_text(actual)


def _normalize_text(value: str) -> str:
    normalized = unicodedata.normalize("NFKC", value).casefold()
    return " ".join(normalized.split())


def _date_values(item: BenchmarkItem, prediction: BenchmarkPrediction) -> tuple[date, date | None]:
    if item.expected.is_all_day:
        expected = date.fromisoformat(item.expected.start)
    else:
        expected = _localized_datetime(item.expected.start, item.timezone).date()
    if prediction.start is None:
        return expected, None
    try:
        if prediction.is_all_day:
            actual = date.fromisoformat(prediction.start)
        else:
            actual = _localized_datetime(prediction.start, item.timezone).date()
    except ValueError as error:
        raise BenchmarkValidationError(
            f"{prediction.item_id}: prediction start is not valid for scoring"
        ) from error
    return expected, actual


def _time_values(item: BenchmarkItem, prediction: BenchmarkPrediction) -> tuple[tuple[int, int], tuple[int, int] | None]:
    expected_datetime = _localized_datetime(item.expected.start, item.timezone)
    expected = (expected_datetime.hour, expected_datetime.minute)
    if prediction.start is None or prediction.is_all_day:
        return expected, None
    actual_datetime = _localized_datetime(prediction.start, item.timezone)
    return expected, (actual_datetime.hour, actual_datetime.minute)


def _localized_datetime(value: str, timezone: str) -> datetime:
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("explicit UTC offset required")
    return parsed.astimezone(ZoneInfo(timezone))
