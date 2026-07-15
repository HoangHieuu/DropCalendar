from __future__ import annotations

from snapcal_benchmark.metrics import score_predictions
from snapcal_benchmark.models import (
    BenchmarkItem,
    BenchmarkPrediction,
    ExpectedEvent,
    Provenance,
)


def test_scores_language_metrics_and_wrong_critical_values_without_leaking_values() -> None:
    items = [
        _item("vi-item", "vietnamese", "Hội thảo AI", "2026-08-15T20:00:00+07:00"),
        _item("en-item", "english", "AI Meetup", "2026-08-16T19:00:00+07:00"),
    ]
    predictions = [
        _prediction("vi-item", "Hội thảo AI", "2026-08-15T20:00:00+07:00", 900),
        _prediction("en-item", "AI Meetup", "2026-08-17T19:00:00+07:00", 1_100),
    ]

    report = score_predictions(items, predictions, mode="local_only")

    assert report["metrics"]["vietnamese"]["date_accuracy"] == 1
    assert report["metrics"]["english"]["date_accuracy"] == 0
    assert report["metrics"]["all"]["median_latency_ms"] == 1_000
    assert report["metrics"]["all"]["p90_latency_ms"] == 1_080
    assert report["metrics"]["all"]["p95_latency_ms"] == 1_090
    assert report["metrics"]["all"]["date_wrong_count"] == 1
    assert report["metrics"]["all"]["time_wrong_count"] == 0
    assert report["failure_counts"]["problem_by_language"] == {"english": 1}
    assert report["failure_counts"]["problem_by_source_category"] == {"workshop": 1}
    assert report["failure_counts"]["problem_by_difficulty"] == {"clean": 1}
    assert report["claim_scope"] == "synthetic_regression_only"
    assert report["failures"] == [{
        "item_id": "en-item",
        "language": "english",
        "source_category": "workshop",
        "difficulties": ["clean"],
        "failure_reason": None,
        "mismatch_fields": ["date"],
        "missed_ambiguity_fields": [],
        "unexpected_ambiguity_fields": [],
        "latency_ms": 1_100,
    }]
    rendered = str(report)
    assert "AI Meetup" not in rendered
    assert "2026-08-17" not in rendered


def test_missing_critical_value_is_incorrect_but_not_counted_as_wrong() -> None:
    item = _item("vi-item", "vietnamese", "Hội thảo AI", "2026-08-15T20:00:00+07:00")
    prediction = BenchmarkPrediction(
        schema_version=1,
        item_id="vi-item",
        mode="local_only",
        outcome="draft",
        title="Hội thảo AI",
        start=None,
        end=None,
        is_all_day=False,
        location="Đại học Bách Khoa",
        evidence_fields=("title", "location"),
        ambiguity_fields=("dateTime",),
        latency_ms=500,
        failure_reason=None,
    )

    report = score_predictions([item], [prediction], mode="local_only")

    assert report["metrics"]["all"]["date_accuracy"] == 0
    assert report["metrics"]["all"]["time_accuracy"] == 0
    assert report["metrics"]["all"]["critical_wrong_rate"] == 0
    assert report["metrics"]["all"]["critical_missing_count"] == 2
    assert report["metrics"]["all"]["date_missing_count"] == 1
    assert report["metrics"]["all"]["time_missing_count"] == 1
    assert "vietnamese_or_mixed.title_accuracy" not in report["quality_gates"]["checks"]
    assert report["quality_gates"]["profile"] == "local_only"


def test_scores_manifest_ambiguity_fields_against_domain_field_names() -> None:
    item = _item("ambiguous", "english", "AI Meetup", "2026-08-16T19:00:00+07:00")
    item = BenchmarkItem(
        **{
            **item.__dict__,
            "expected_ambiguity_fields": ("start", "location"),
        }
    )
    prediction = BenchmarkPrediction(
        **{
            **_prediction(
                "ambiguous",
                "AI Meetup",
                "2026-08-16T19:00:00+07:00",
                500,
            ).__dict__,
            "mode": "accuracy",
            "ambiguity_fields": ("dateTime", "title"),
        }
    )

    report = score_predictions([item], [prediction], mode="accuracy")
    metrics = report["metrics"]["all"]

    assert metrics["ambiguity_expected_field_count"] == 2
    assert metrics["ambiguity_predicted_field_count"] == 2
    assert metrics["ambiguity_true_positive_field_count"] == 1
    assert metrics["ambiguity_missed_field_count"] == 1
    assert metrics["ambiguity_unexpected_field_count"] == 1
    assert metrics["ambiguity_precision"] == 0.5
    assert metrics["ambiguity_recall"] == 0.5
    assert metrics["ambiguity_exact_item_rate"] == 0
    assert report["failure_counts"]["problem_by_reason"] == {
        "missed_expected_ambiguity": 1
    }


def test_accuracy_profile_enforces_semantic_targets_but_local_profile_does_not() -> None:
    item = _item("en-item", "english", "Expected", "2026-08-16T19:00:00+07:00")
    wrong = _prediction("en-item", "Wrong", "2026-08-16T19:00:00+07:00", 500)

    local_report = score_predictions([item], [wrong], mode="local_only")
    accuracy_prediction = BenchmarkPrediction(**{**wrong.__dict__, "mode": "accuracy"})
    accuracy_report = score_predictions([item], [accuracy_prediction], mode="accuracy")

    assert local_report["quality_gates"]["passed"] is True
    assert local_report["quality_gates"]["checks"] == {
        "all.critical_wrong_rate": True,
        "all.median_latency_ms": True,
        "all.critical_evidence_coverage": True,
    }
    assert accuracy_report["quality_gates"]["passed"] is False
    assert accuracy_report["quality_gates"]["checks"]["english.title_accuracy"] is False


def _item(item_id: str, language: str, title: str, start: str) -> BenchmarkItem:
    return BenchmarkItem(
        schema_version=1,
        item_id=item_id,
        image=f"images/{item_id}.png",
        image_sha256="0" * 64,
        language=language,
        source_category="workshop",
        difficulties=("clean",),
        captured_at="2026-07-14T09:00:00+07:00",
        timezone="Asia/Ho_Chi_Minh",
        expected=ExpectedEvent(
            title=title,
            start=start,
            end=None,
            is_all_day=False,
            location="Đại học Bách Khoa",
        ),
        provenance=Provenance(
            kind="generated",
            source="test",
            rights_holder="test",
            license_or_permission="test",
            redistributable=True,
        ),
        sanitized=True,
        synthetic=True,
    )


def _prediction(item_id: str, title: str, start: str, latency_ms: float) -> BenchmarkPrediction:
    return BenchmarkPrediction(
        schema_version=1,
        item_id=item_id,
        mode="local_only",
        outcome="draft",
        title=title,
        start=start,
        end=None,
        is_all_day=False,
        location="Đại học Bách Khoa",
        evidence_fields=("title", "start", "location"),
        ambiguity_fields=(),
        latency_ms=latency_ms,
        failure_reason=None,
    )
