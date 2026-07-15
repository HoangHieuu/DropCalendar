from __future__ import annotations

import hashlib
import json
from pathlib import Path

import pytest

from snapcal_benchmark.review_promotion import (
    ReviewPromotionError,
    create_review_template,
    promote_reviews,
)
from snapcal_benchmark.validation import (
    BenchmarkValidationError,
    load_manifest,
    validate_corpus,
)


def write_jsonl(path: Path, rows: list[dict[str, object]]) -> None:
    path.write_text(
        "".join(json.dumps(row, sort_keys=True) + "\n" for row in rows),
        encoding="utf-8",
    )


def build_intake(
    root: Path, count: int
) -> tuple[Path, Path, list[dict[str, object]]]:
    images = root / "images"
    images.mkdir(parents=True)
    candidates: list[dict[str, object]] = []
    queue: list[dict[str, object]] = []
    for index in range(count):
        content = b"\x89PNG\r\n\x1a\n" + f"private-{index}".encode()
        digest = hashlib.sha256(content).hexdigest()
        image = images / f"source-{index}.png"
        image.write_bytes(content)
        item_id = f"commons-{digest[:16]}"
        candidates.append({
            "schema_version": 1,
            "status": "candidate",
            "commons_title": f"File:Poster {index}.png",
            "local_image": f"images/source-{index}.png",
            "image_sha256": digest,
            "description_url": (
                f"https://commons.wikimedia.org/wiki/File:Poster_{index}.png"
            ),
            "license_short_name": "CC BY 4.0",
            "license_url": "https://creativecommons.org/licenses/by/4.0/",
            "artist": "Example Artist",
            "attribution": "Example Artist",
            "machine_license_allowlisted": True,
            "license_reviewed": False,
            "sanitized": False,
            "cloud_processing_authorized": False,
        })
        queue.append({
            "candidate_id": item_id,
            "image_sha256": digest,
            "language_hint": "vietnamese",
            "source_category_hint": "general_event",
            "difficulty_hints": [],
            "likely_event_image": True,
        })
    candidates_path = root / "candidates.jsonl"
    queue_path = root / "review-queue.jsonl"
    write_jsonl(candidates_path, candidates)
    write_jsonl(queue_path, queue)
    return candidates_path, queue_path, queue


def approved_decision(
    queue_row: dict[str, object], index: int
) -> dict[str, object]:
    return {
        "schema_version": 1,
        "candidate_id": queue_row["candidate_id"],
        "image_sha256": queue_row["image_sha256"],
        "decision": "approve",
        "language": "vietnamese" if index < 10 else "english",
        "source_category": "workshop",
        "difficulties": ["noisy"] if index < 4 else [],
        "captured_at": "2026-07-15T09:00:00+07:00",
        "timezone": "Asia/Ho_Chi_Minh",
        "expected": {
            "title": f"Reviewed event {index}",
            "start": "2026-07-20T09:00:00+07:00",
            "end": "2026-07-20T10:00:00+07:00",
            "is_all_day": False,
            "location": "Hanoi",
        },
        "expected_ambiguity_fields": [],
        "provenance": {
            "kind": "cc",
            "source": (
                f"https://commons.wikimedia.org/wiki/File:Poster_{index}.png"
            ),
            "rights_holder": "Example Artist",
            "license_or_permission": "CC BY 4.0",
            "redistributable": False,
        },
        "license_reviewed": True,
        "sanitized": True,
        "ground_truth_annotated": True,
        "benchmark_use_authorized": True,
        "cloud_processors": ["openrouter"],
        "authorization_reference": f"review-record-{index}",
        "primary_reviewer": "reviewer-a",
        "primary_reviewed_at": "2026-07-15T10:00:00+07:00",
        "critical_fields_second_reviewed": True,
        "second_reviewer": "reviewer-b",
        "second_reviewed_at": "2026-07-15T11:00:00+07:00",
        "machine_hints": {},
        "reviewer_notes": "",
    }


def test_template_keeps_every_human_gate_false_and_excludes_ocr_text(
    tmp_path: Path,
) -> None:
    candidates, queue, _ = build_intake(tmp_path / "intake", 2)
    output = tmp_path / "review" / "decisions.jsonl"

    summary = create_review_template(candidates, queue, output)
    rows = [json.loads(line) for line in output.read_text().splitlines()]

    assert summary["item_count"] == 2
    assert summary["approved_count"] == 0
    assert all(row["decision"] == "pending" for row in rows)
    assert all(row["license_reviewed"] is False for row in rows)
    assert all(row["sanitized"] is False for row in rows)
    assert all(row["benchmark_use_authorized"] is False for row in rows)
    assert all(row["critical_fields_second_reviewed"] is False for row in rows)
    assert all("ocr_text" not in row for row in rows)


def test_template_refuses_to_overwrite_human_work(tmp_path: Path) -> None:
    candidates, queue, _ = build_intake(tmp_path / "intake", 1)
    output = tmp_path / "decisions.jsonl"
    output.write_text("human edit", encoding="utf-8")

    with pytest.raises(ReviewPromotionError, match="refusing to overwrite"):
        create_review_template(candidates, queue, output)


def test_promotion_requires_explicit_human_approvals(tmp_path: Path) -> None:
    candidates, _, queue = build_intake(tmp_path / "intake", 1)
    decision = approved_decision(queue[0], 0)
    decision["sanitized"] = False
    decisions = tmp_path / "decisions.jsonl"
    write_jsonl(decisions, [decision])
    output = tmp_path / "corpus"

    with pytest.raises(
        ReviewPromotionError, match="sanitized must be explicitly true"
    ):
        promote_reviews(candidates, decisions, output, profile="calibration")
    assert not output.exists()


def test_promotion_requires_an_independent_second_reviewer(
    tmp_path: Path,
) -> None:
    candidates, _, queue = build_intake(tmp_path / "intake", 1)
    decision = approved_decision(queue[0], 0)
    decision["second_reviewer"] = "REVIEWER-A"
    decisions = tmp_path / "decisions.jsonl"
    write_jsonl(decisions, [decision])

    with pytest.raises(
        ReviewPromotionError, match="second reviewer must be independent"
    ):
        promote_reviews(
            candidates, decisions, tmp_path / "corpus", profile="calibration"
        )


def test_promotes_exactly_twenty_reviewed_items_to_private_calibration_corpus(
    tmp_path: Path,
) -> None:
    candidates, _, queue = build_intake(tmp_path / "intake", 20)
    decisions = tmp_path / "decisions.jsonl"
    write_jsonl(
        decisions,
        [approved_decision(row, index) for index, row in enumerate(queue)],
    )
    output = tmp_path / "calibration"

    summary = promote_reviews(
        candidates,
        decisions,
        output,
        profile="calibration",
    )

    manifest = output / "manifest.jsonl"
    items = load_manifest(manifest)
    validation = validate_corpus(
        items,
        manifest_path=manifest,
        require_calibration=True,
        require_real_world=True,
        require_cloud_authorized="openrouter",
        require_second_reviewed=True,
    )
    assert summary["item_count"] == 20
    assert validation.total == 20
    assert len(list((output / "images").iterdir())) == 20


def test_acceptance_profile_rejects_an_incomplete_corpus_without_leaving_output(
    tmp_path: Path,
) -> None:
    candidates, _, queue = build_intake(tmp_path / "intake", 1)
    decisions = tmp_path / "decisions.jsonl"
    write_jsonl(decisions, [approved_decision(queue[0], 0)])
    output = tmp_path / "acceptance"

    with pytest.raises(
        BenchmarkValidationError, match="requires at least 100 items"
    ):
        promote_reviews(candidates, decisions, output, profile="acceptance")
    assert not output.exists()
