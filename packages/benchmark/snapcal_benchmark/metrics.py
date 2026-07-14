from __future__ import annotations

import json
import statistics
import unicodedata
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
    gates = _quality_gates(metrics)
    failures = []
    for item in items:
        prediction = prediction_by_id[item.item_id]
        mismatches = _mismatch_fields(item, prediction)
        if prediction.outcome == "failure" or mismatches:
            failures.append({
                "item_id": item.item_id,
                "language": item.language,
                "failure_reason": prediction.failure_reason,
                "mismatch_fields": mismatches,
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
        }

    title_correct = 0
    date_correct = 0
    timed_items = 0
    time_correct = 0
    location_items = 0
    location_correct = 0
    wrong_critical = 0
    critical_denominator = 0
    critical_evidence_present = 0
    critical_evidence_denominator = 0
    structured_failures = 0
    latencies: list[float] = []

    for item in items:
        prediction = prediction_by_id[item.item_id]
        latencies.append(prediction.latency_ms)
        if prediction.outcome == "failure":
            structured_failures += 1
        title_correct += _text_equal(item.expected.title, prediction.title)
        expected_date, predicted_date = _date_values(item, prediction)
        date_correct += expected_date == predicted_date
        critical_denominator += 1
        if predicted_date is not None and predicted_date != expected_date:
            wrong_critical += 1
        if not item.expected.is_all_day:
            timed_items += 1
            expected_time, predicted_time = _time_values(item, prediction)
            time_correct += expected_time == predicted_time
            critical_denominator += 1
            if predicted_time is not None and predicted_time != expected_time:
                wrong_critical += 1
        if item.expected.location is not None:
            location_items += 1
            location_correct += _text_equal(item.expected.location, prediction.location)
        expected_evidence = ["title", "start"]
        if item.expected.location is not None:
            expected_evidence.append("location")
        critical_evidence_denominator += len(expected_evidence)
        critical_evidence_present += len(set(expected_evidence) & set(prediction.evidence_fields))

    count = len(items)
    return {
        "count": count,
        "title_accuracy": title_correct / count,
        "date_accuracy": date_correct / count,
        "time_accuracy": time_correct / timed_items if timed_items else None,
        "location_accuracy": location_correct / location_items if location_items else None,
        "critical_wrong_rate": wrong_critical / critical_denominator,
        "structured_failure_rate": structured_failures / count,
        "critical_evidence_coverage": (
            critical_evidence_present / critical_evidence_denominator
            if critical_evidence_denominator
            else None
        ),
        "median_latency_ms": statistics.median(latencies),
    }


def _quality_gates(metrics: dict[str, dict[str, Any]]) -> dict[str, Any]:
    checks: dict[str, bool | None] = {}
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
    evaluated = [value for value in checks.values() if value is not None]
    return {"passed": bool(evaluated) and all(evaluated), "checks": checks}


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
