from __future__ import annotations

from dataclasses import dataclass
from typing import Any


SCHEMA_VERSION = 1
MANIFEST_SCHEMA_VERSIONS = frozenset({1, 2})
LANGUAGES = frozenset({"vietnamese", "english", "mixed"})
MODES = frozenset({"local_only", "accuracy"})
OUTCOMES = frozenset({"draft", "failure"})
SOURCE_CATEGORIES = frozenset({
    "facebook",
    "tiktok",
    "instagram",
    "website",
    "university",
    "workshop",
    "hackathon",
    "concert",
    "webinar",
    "online_event",
})
DIFFICULTIES = frozenset({
    "clean",
    "noisy",
    "low_resolution",
    "decorative_font",
    "mixed_language",
    "dense_layout",
})
PROVENANCE_KINDS = frozenset({"owned", "permission", "cc", "generated"})
FAILURE_REASONS = frozenset({
    "unsupported_image",
    "corrupt_image",
    "no_event_detected",
    "insufficient_event_evidence",
    "provider_unavailable",
    "provider_rejected_input",
    "invalid_provider_output",
    "extraction_timeout",
})
EXPECTED_AMBIGUITY_FIELDS = frozenset({"title", "start", "end", "location"})
CLOUD_PROCESSORS = frozenset({"openrouter"})


@dataclass(frozen=True)
class Provenance:
    kind: str
    source: str
    rights_holder: str
    license_or_permission: str
    redistributable: bool


@dataclass(frozen=True)
class ExpectedEvent:
    title: str
    start: str
    end: str | None
    is_all_day: bool
    location: str | None


@dataclass(frozen=True)
class ProcessingAuthorization:
    benchmark_use: bool
    cloud_processors: tuple[str, ...]
    authorization_reference: str


@dataclass(frozen=True)
class Annotation:
    critical_fields_second_reviewed: bool
    reviewed_at: str


@dataclass(frozen=True)
class BenchmarkItem:
    schema_version: int
    item_id: str
    image: str
    image_sha256: str
    language: str
    source_category: str
    difficulties: tuple[str, ...]
    captured_at: str
    timezone: str
    expected: ExpectedEvent
    provenance: Provenance
    sanitized: bool
    synthetic: bool
    expected_ambiguity_fields: tuple[str, ...] = ()
    processing_authorization: ProcessingAuthorization | None = None
    annotation: Annotation | None = None


@dataclass(frozen=True)
class BenchmarkPrediction:
    schema_version: int
    item_id: str
    mode: str
    outcome: str
    title: str | None
    start: str | None
    end: str | None
    is_all_day: bool | None
    location: str | None
    evidence_fields: tuple[str, ...]
    ambiguity_fields: tuple[str, ...]
    latency_ms: float
    failure_reason: str | None


@dataclass(frozen=True)
class ValidationSummary:
    total: int
    vietnamese_or_mixed: int
    english: int
    challenging: int
    synthetic: int
    non_synthetic: int
    source_categories: tuple[str, ...]

    def as_dict(self) -> dict[str, Any]:
        return {
            "total": self.total,
            "vietnamese_or_mixed": self.vietnamese_or_mixed,
            "english": self.english,
            "challenging": self.challenging,
            "synthetic": self.synthetic,
            "non_synthetic": self.non_synthetic,
            "source_categories": list(self.source_categories),
        }
