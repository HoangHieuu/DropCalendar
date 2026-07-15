from __future__ import annotations

import json
from pathlib import Path

from snapcal_benchmark.commons_import import (
    clean_metadata_text,
    commons_title_from_url,
    is_allowed_license,
    load_discovered_files,
    rejection_reason,
    select_balanced,
)


def test_extracts_file_title_from_commons_thumbnail_and_original_urls() -> None:
    assert commons_title_from_url(
        "https://upload.wikimedia.org/wikipedia/commons/thumb/f/f5/1982-us.jpg/120px-1982-us.jpg"
    ) == "File:1982-us.jpg"
    assert commons_title_from_url(
        "https://upload.wikimedia.org/wikipedia/commons/a/ab/My%20Poster.png"
    ) == "File:My Poster.png"
    assert commons_title_from_url("https://example.com/poster.jpg") is None


def test_deduplicates_apify_rows_and_preserves_discovery_sources(tmp_path: Path) -> None:
    metadata_path = tmp_path / "metadata.json"
    metadata_path.write_text(json.dumps([
        {
            "imageUrl": "https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/Poster.jpg/120px-Poster.jpg",
            "scrapedFromUrl": "https://commons.wikimedia.org/wiki/Category:Concert_posters",
        },
        {
            "imageUrl": "https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/Poster.jpg/240px-Poster.jpg",
            "scrapedFromUrl": "https://commons.wikimedia.org/wiki/Category:Festival_posters",
        },
        {"imageUrl": "https://commons.wikimedia.org/static/logo.svg"},
    ]), encoding="utf-8")

    files = load_discovered_files([metadata_path])

    assert len(files) == 1
    assert files[0].title == "File:Poster.jpg"
    assert files[0].source_pages == (
        "https://commons.wikimedia.org/wiki/Category:Concert_posters",
        "https://commons.wikimedia.org/wiki/Category:Festival_posters",
    )


def test_license_allowlist_rejects_restricted_and_unclear_terms() -> None:
    assert is_allowed_license("Public domain")
    assert is_allowed_license("CC0 1.0")
    assert is_allowed_license("CC BY 4.0")
    assert is_allowed_license("CC BY-SA 3.0")
    assert not is_allowed_license("CC BY-NC 4.0")
    assert not is_allowed_license("CC BY-ND 4.0")
    assert not is_allowed_license("Copyrighted")
    assert not is_allowed_license("")


def test_candidate_gate_requires_license_resolution_and_safe_download_url() -> None:
    item = {
        "license_short_name": "CC BY-SA 4.0",
        "mime": "image/jpeg",
        "original_width": 1200,
        "original_height": 900,
        "download_url": "https://upload.wikimedia.org/wikipedia/commons/a/ab/poster.jpg",
    }

    assert rejection_reason(item, min_long_edge=800, min_short_edge=400) is None
    assert rejection_reason(
        {**item, "download_url": "https://example.com/poster.jpg"},
        min_long_edge=800,
        min_short_edge=400,
    ) == "invalid_download_url"
    assert rejection_reason(
        {**item, "original_height": 200},
        min_long_edge=800,
        min_short_edge=400,
    ) == "insufficient_resolution"


def test_balanced_selection_round_robins_discovery_sources() -> None:
    items = [
        {"title": "File:A1.jpg", "source_pages": ["A"]},
        {"title": "File:A2.jpg", "source_pages": ["A"]},
        {"title": "File:B1.jpg", "source_pages": ["B"]},
        {"title": "File:B2.jpg", "source_pages": ["B"]},
    ]

    assert [item["title"] for item in select_balanced(items, 3)] == [
        "File:A1.jpg",
        "File:B1.jpg",
        "File:A2.jpg",
    ]


def test_cleans_commons_html_metadata() -> None:
    assert clean_metadata_text("<span>Jane &amp; John</span><br>Archive") == "Jane & John Archive"
