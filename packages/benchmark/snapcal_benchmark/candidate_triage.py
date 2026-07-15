from __future__ import annotations

import argparse
import csv
import json
import re
import sys
import unicodedata
from collections import Counter
from pathlib import Path
from typing import Any, Iterable


APPROVAL_FIELDS = (
    "license_reviewed",
    "sanitized",
    "cloud_processing_authorized",
)

VIETNAMESE_TERMS = (
    "biểu diễn",
    "chương trình",
    "cuộc thi",
    "diễn đàn",
    "hòa nhạc",
    "hội nghị",
    "hội thảo",
    "khai mạc",
    "lễ hội",
    "ngày hội",
    "tháng",
    "thứ hai",
    "thứ ba",
    "thứ tư",
    "thứ năm",
    "thứ sáu",
    "thứ bảy",
    "chủ nhật",
    "tọa đàm",
    "triển lãm",
)

ENGLISH_EVENT_TERMS = (
    "conference",
    "concert",
    "event",
    "exhibition",
    "festival",
    "forum",
    "meeting",
    "meetup",
    "seminar",
    "summit",
    "talk",
    "webinar",
    "workshop",
)

ENGLISH_DATE_TERMS = (
    "monday",
    "tuesday",
    "wednesday",
    "thursday",
    "friday",
    "saturday",
    "sunday",
    "january",
    "february",
    "march",
    "april",
    "may",
    "june",
    "july",
    "august",
    "september",
    "october",
    "november",
    "december",
)

DATE_PATTERNS = (
    re.compile(r"(?<!\d)(?:0?[1-9]|[12]\d|3[01])[./-](?:0?[1-9]|1[0-2])(?:[./-](?:19|20)?\d{2})?(?!\d)"),
    re.compile(r"(?<!\d)(?:19|20)\d{2}[./-](?:0?[1-9]|1[0-2])[./-](?:0?[1-9]|[12]\d|3[01])(?!\d)"),
)

TIME_PATTERNS = (
    re.compile(r"(?<!\d)(?:[01]?\d|2[0-3])[:.]\d{2}(?!\d)"),
    re.compile(r"(?<!\d)(?:1[0-2]|0?[1-9])(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)\b", re.IGNORECASE),
    re.compile(r"(?<!\d)(?:[01]?\d|2[0-3])\s*(?:h|giờ)(?:\s*\d{1,2})?(?!\d)", re.IGNORECASE),
)

VIETNAMESE_LANGUAGE_TERMS = (
    "biểu diễn",
    "chương trình",
    "chủ nhật",
    "đăng ký",
    "địa điểm",
    "hòa nhạc",
    "hội nghị",
    "hội thảo",
    "lễ hội",
    "lúc ",
    "ngày ",
    "phim",
    "thành phố",
    "tháng ",
    "thứ bảy",
    "tọa đàm",
    "triển lãm",
    "việt nam",
)

VIETNAMESE_DISTINCTIVE_CHARACTERS = frozenset(
    "ăđơưảạấầẩẫậắằẳẵặẻẽẹếềểễệỉĩịỏọốồổỗộớờởỡợủũụứừửữựỷỹỵ"
)


class CandidateTriageError(ValueError):
    pass


def _load_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        try:
            row = json.loads(line)
        except json.JSONDecodeError as error:
            raise CandidateTriageError(f"{path}:{line_number}: invalid JSON: {error}") from error
        if not isinstance(row, dict):
            raise CandidateTriageError(f"{path}:{line_number}: row must be an object")
        rows.append(row)
    return rows


def _contains_any(text: str, terms: Iterable[str]) -> bool:
    return any(term in text for term in terms)


def _has_pattern(text: str, patterns: Iterable[re.Pattern[str]]) -> bool:
    return any(pattern.search(text) for pattern in patterns)


def _has_vietnamese_signal(text: str) -> bool:
    lowered = text.casefold()
    normalized = unicodedata.normalize("NFC", lowered)
    if _contains_any(normalized, VIETNAMESE_LANGUAGE_TERMS):
        return True
    return sum(character in VIETNAMESE_DISTINCTIVE_CHARACTERS for character in normalized) >= 2


def classify_language(text: str) -> str:
    lowered = text.casefold()
    vietnamese = _has_vietnamese_signal(lowered)
    english = _contains_any(lowered, ENGLISH_EVENT_TERMS + ENGLISH_DATE_TERMS)
    if vietnamese and english:
        return "mixed"
    if vietnamese:
        return "vietnamese"
    if english:
        return "english"
    return "undetermined"


def source_category(candidate: dict[str, Any]) -> str:
    source_text = " ".join(str(value) for value in candidate.get("source_pages", [])).casefold()
    title = str(candidate.get("commons_title", "")).casefold()
    combined = source_text + " " + title
    categories = (
        ("conference", ("conference", "seminar", "symposium", "summit")),
        ("concert", ("concert", "music", "gig")),
        ("festival", ("festival", "fair")),
        ("theatre", ("theatre", "theater", "playbill")),
        ("sports", ("sport", "olympic", "tournament", "race")),
        ("community", ("meetup", "wikimania", "community", "meeting")),
        ("general_event", ("event", "poster", "flyer")),
    )
    for category, terms in categories:
        if any(term in combined for term in terms):
            return category
    return "other"


def triage_candidate(candidate: dict[str, Any], ocr: dict[str, Any]) -> dict[str, Any]:
    for field in APPROVAL_FIELDS:
        if candidate.get(field) is not False:
            raise CandidateTriageError(
                f"{candidate.get('commons_title', '<unknown>')}: {field} must remain false during triage"
            )

    if candidate.get("image_sha256") != ocr.get("image_sha256"):
        raise CandidateTriageError(
            f"{candidate.get('commons_title', '<unknown>')}: OCR result SHA-256 does not match"
        )

    lines = ocr.get("lines", [])
    if not isinstance(lines, list):
        raise CandidateTriageError(f"{ocr.get('candidate_id', '<unknown>')}: lines must be an array")
    text_lines = [str(line.get("text", "")).strip() for line in lines if isinstance(line, dict)]
    text_lines = [line for line in text_lines if line]
    full_text = "\n".join(text_lines)
    lowered = full_text.casefold()
    confidences = [
        float(line["confidence"])
        for line in lines
        if isinstance(line, dict) and isinstance(line.get("confidence"), (int, float))
    ]
    average_confidence = sum(confidences) / len(confidences) if confidences else 0.0
    has_date = _has_pattern(lowered, DATE_PATTERNS) or _contains_any(
        lowered, VIETNAMESE_TERMS[10:] + ENGLISH_DATE_TERMS
    )
    has_time = _has_pattern(lowered, TIME_PATTERNS)
    has_event_term = _contains_any(lowered, VIETNAMESE_TERMS[:10] + ENGLISH_EVENT_TERMS)
    language = classify_language(full_text)

    score = 0
    score += 35 if has_date else 0
    score += 25 if has_time else 0
    score += 20 if has_event_term else 0
    score += 10 if len(text_lines) >= 4 else 0
    score += 5 if language in {"vietnamese", "mixed"} else 0
    score += 5 if average_confidence >= 0.75 else 0
    likely_event = has_date and (has_time or has_event_term) and len(text_lines) >= 3

    long_edge = max(int(candidate.get("review_width") or 0), int(candidate.get("review_height") or 0))
    short_edge = min(int(candidate.get("review_width") or 0), int(candidate.get("review_height") or 0))
    difficulty_hints: list[str] = []
    if average_confidence and average_confidence < 0.75:
        difficulty_hints.append("low_ocr_confidence")
    if short_edge and short_edge < 600:
        difficulty_hints.append("low_resolution")
    if len(text_lines) >= 20:
        difficulty_hints.append("dense_text")
    if long_edge and short_edge and long_edge / short_edge >= 2.5:
        difficulty_hints.append("extreme_aspect_ratio")

    return {
        "schema_version": 1,
        "candidate_id": ocr.get("candidate_id"),
        "status": "needs_human_review",
        "commons_title": candidate.get("commons_title"),
        "local_image": candidate.get("local_image"),
        "image_sha256": candidate.get("image_sha256"),
        "description_url": candidate.get("description_url"),
        "source_pages": candidate.get("source_pages", []),
        "license_short_name": candidate.get("license_short_name"),
        "license_url": candidate.get("license_url"),
        "artist": candidate.get("artist"),
        "attribution": candidate.get("attribution"),
        "machine_license_allowlisted": candidate.get("machine_license_allowlisted") is True,
        "license_reviewed": False,
        "sanitized": False,
        "cloud_processing_authorized": False,
        "ground_truth_annotated": False,
        "critical_fields_second_reviewed": False,
        "ocr_outcome": ocr.get("outcome"),
        "ocr_failure_reason": ocr.get("failure_reason"),
        "ocr_line_count": len(text_lines),
        "ocr_average_confidence": round(average_confidence, 4),
        "ocr_text": full_text,
        "has_date_signal": has_date,
        "has_time_signal": has_time,
        "has_event_term": has_event_term,
        "likely_event_image": likely_event,
        "language_hint": language,
        "source_category_hint": source_category(candidate),
        "difficulty_hints": difficulty_hints,
        "review_priority": score,
        "reviewer_decision": "",
        "reviewer_notes": "",
    }


def _write_jsonl(path: Path, rows: Iterable[dict[str, Any]]) -> None:
    with path.open("w", encoding="utf-8") as output:
        for row in rows:
            output.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n")


def write_review_worksheet(path: Path, rows: list[dict[str, Any]]) -> None:
    fieldnames = (
        "review_priority",
        "candidate_id",
        "likely_event_image",
        "language_hint",
        "source_category_hint",
        "has_date_signal",
        "has_time_signal",
        "has_event_term",
        "ocr_line_count",
        "ocr_average_confidence",
        "difficulty_hints",
        "commons_title",
        "local_image",
        "description_url",
        "license_short_name",
        "ocr_preview",
        "reviewer_decision",
        "reviewer_notes",
    )
    with path.open("w", encoding="utf-8", newline="") as output:
        writer = csv.DictWriter(output, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            worksheet_row = {key: row.get(key, "") for key in fieldnames}
            worksheet_row["difficulty_hints"] = ";".join(row["difficulty_hints"])
            worksheet_row["ocr_preview"] = " | ".join(row["ocr_text"].splitlines())[:500]
            writer.writerow(worksheet_row)


def triage_candidates(candidates_path: Path, ocr_path: Path, output_dir: Path) -> dict[str, Any]:
    candidates = _load_jsonl(candidates_path)
    ocr_rows = _load_jsonl(ocr_path)
    candidates_by_hash = {str(row.get("image_sha256")): row for row in candidates}
    ocr_by_hash = {str(row.get("image_sha256")): row for row in ocr_rows}
    if len(candidates_by_hash) != len(candidates):
        raise CandidateTriageError("candidate SHA-256 values must be unique")
    if len(ocr_by_hash) != len(ocr_rows):
        raise CandidateTriageError("OCR result SHA-256 values must be unique")
    if set(candidates_by_hash) != set(ocr_by_hash):
        raise CandidateTriageError("OCR results must cover every candidate exactly once")

    rows = [triage_candidate(candidate, ocr_by_hash[sha]) for sha, candidate in candidates_by_hash.items()]
    rows.sort(key=lambda row: (-int(row["review_priority"]), str(row["candidate_id"])))
    output_dir.mkdir(parents=True, exist_ok=True)
    _write_jsonl(output_dir / "review-queue.jsonl", rows)
    write_review_worksheet(output_dir / "review-worksheet.csv", rows)

    language_counts = Counter(str(row["language_hint"]) for row in rows)
    source_counts = Counter(str(row["source_category_hint"]) for row in rows)
    summary = {
        "schema_version": 1,
        "candidate_count": len(rows),
        "ocr_recognized_count": sum(row["ocr_outcome"] == "recognized" for row in rows),
        "likely_event_count": sum(bool(row["likely_event_image"]) for row in rows),
        "date_signal_count": sum(bool(row["has_date_signal"]) for row in rows),
        "time_signal_count": sum(bool(row["has_time_signal"]) for row in rows),
        "language_hint_counts": dict(sorted(language_counts.items())),
        "source_category_hint_counts": dict(sorted(source_counts.items())),
        "license_reviewed_count": 0,
        "sanitized_count": 0,
        "cloud_processing_authorized_count": 0,
        "ground_truth_annotated_count": 0,
        "critical_fields_second_reviewed_count": 0,
        "benchmark_ready": False,
        "notice": "Machine triage is preliminary and cannot replace rights, privacy, annotation, authorization, or second review.",
    }
    (output_dir / "triage-summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return summary


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Create a local-only, non-authoritative human review queue for benchmark candidates."
    )
    parser.add_argument("--candidates", type=Path, required=True)
    parser.add_argument("--ocr-results", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        summary = triage_candidates(args.candidates, args.ocr_results, args.output_dir)
    except (OSError, CandidateTriageError) as error:
        print(f"candidate triage failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(summary, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
