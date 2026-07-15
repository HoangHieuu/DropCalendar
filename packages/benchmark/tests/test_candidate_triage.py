from __future__ import annotations

import json
from pathlib import Path

import pytest

from snapcal_benchmark.candidate_triage import (
    CandidateTriageError,
    classify_language,
    source_category,
    triage_candidate,
    triage_candidates,
)


def candidate(**overrides: object) -> dict[str, object]:
    base: dict[str, object] = {
        "commons_title": "File:Workshop poster.jpg",
        "local_image": "images/poster.jpg",
        "image_sha256": "abc123",
        "description_url": "https://commons.wikimedia.org/wiki/File:Workshop_poster.jpg",
        "source_pages": ["https://commons.wikimedia.org/wiki/Category:Conference_posters"],
        "license_short_name": "CC BY-SA 4.0",
        "license_url": "https://creativecommons.org/licenses/by-sa/4.0",
        "artist": "Example",
        "attribution": "Example",
        "machine_license_allowlisted": True,
        "license_reviewed": False,
        "sanitized": False,
        "cloud_processing_authorized": False,
        "review_width": 1200,
        "review_height": 800,
    }
    base.update(overrides)
    return base


def ocr(lines: list[tuple[str, float]]) -> dict[str, object]:
    return {
        "candidate_id": "commons-abc123",
        "image_sha256": "abc123",
        "outcome": "recognized",
        "failure_reason": None,
        "lines": [{"text": text, "confidence": confidence} for text, confidence in lines],
    }


def test_ranks_vietnamese_event_with_date_and_time_for_review() -> None:
    result = triage_candidate(candidate(), ocr([
        ("HỘI THẢO CÔNG NGHỆ", 0.95),
        ("15/07/2026", 0.93),
        ("19:30", 0.92),
        ("Nhà Văn hóa Thanh niên", 0.89),
    ]))

    assert result["likely_event_image"] is True
    assert result["language_hint"] == "vietnamese"
    assert result["has_date_signal"] is True
    assert result["has_time_signal"] is True
    assert result["review_priority"] == 100
    assert result["status"] == "needs_human_review"
    assert result["ground_truth_annotated"] is False


def test_classifies_mixed_language_without_claiming_authoritative_language() -> None:
    assert classify_language("Hội thảo AI Conference\nThứ bảy, 15/07") == "mixed"
    assert classify_language("Workshop on July 15") == "english"
    assert classify_language("Arnošt Hofbauer XIII. Výstava Mánesa") == "undetermined"
    assert classify_language("Editatona Paralímpica") == "undetermined"
    assert classify_language("12345") == "undetermined"


def test_preserves_human_approval_boundary() -> None:
    with pytest.raises(CandidateTriageError, match="license_reviewed must remain false"):
        triage_candidate(candidate(license_reviewed=True), ocr([("15/07/2026", 0.9)]))


def test_derives_broad_source_category_only_as_a_hint() -> None:
    assert source_category(candidate()) == "conference"


def test_writes_external_review_queue_and_zero_approval_summary(tmp_path: Path) -> None:
    candidates_path = tmp_path / "candidates.jsonl"
    ocr_path = tmp_path / "ocr.jsonl"
    output_dir = tmp_path / "review"
    candidates_path.write_text(json.dumps(candidate()) + "\n", encoding="utf-8")
    ocr_path.write_text(json.dumps(ocr([
        ("Workshop", 0.9),
        ("July 15, 2026", 0.9),
        ("7:30 PM", 0.9),
    ])) + "\n", encoding="utf-8")

    summary = triage_candidates(candidates_path, ocr_path, output_dir)

    assert summary["candidate_count"] == 1
    assert summary["benchmark_ready"] is False
    assert summary["license_reviewed_count"] == 0
    assert (output_dir / "review-queue.jsonl").is_file()
    assert (output_dir / "review-worksheet.csv").is_file()
    assert (output_dir / "triage-summary.json").is_file()


def test_rejects_duplicate_ocr_results_instead_of_masking_missing_coverage(tmp_path: Path) -> None:
    candidates_path = tmp_path / "candidates.jsonl"
    ocr_path = tmp_path / "ocr.jsonl"
    candidates_path.write_text(json.dumps(candidate()) + "\n", encoding="utf-8")
    ocr_row = json.dumps(ocr([("Workshop", 0.9)]))
    ocr_path.write_text(ocr_row + "\n" + ocr_row + "\n", encoding="utf-8")

    with pytest.raises(CandidateTriageError, match="OCR result SHA-256 values must be unique"):
        triage_candidates(candidates_path, ocr_path, tmp_path / "review")
