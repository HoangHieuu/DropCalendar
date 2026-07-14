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
    assert report["claim_scope"] == "synthetic_regression_only"
    assert report["failures"] == [{
        "item_id": "en-item",
        "language": "english",
        "failure_reason": None,
        "mismatch_fields": ["date"],
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
