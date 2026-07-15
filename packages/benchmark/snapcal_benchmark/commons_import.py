from __future__ import annotations

import argparse
import hashlib
import html
import json
import re
import shutil
import sys
import urllib.parse
import urllib.error
import urllib.request
import time
from collections import defaultdict, deque
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


COMMONS_API = "https://commons.wikimedia.org/w/api.php"
USER_AGENT = (
    "SnapCalBenchmarkImporter/1.0 "
    "(https://github.com/HoangHieuu/DropCalendar; benchmark dataset research)"
)
ALLOWED_MIME_TYPES = frozenset({"image/jpeg", "image/png", "image/webp"})
MAX_BATCH_SIZE = 25


@dataclass(frozen=True)
class DiscoveredFile:
    title: str
    source_pages: tuple[str, ...]
    thumbnail_urls: tuple[str, ...]


def commons_title_from_url(value: str) -> str | None:
    """Return a canonical Commons File title for an upload.wikimedia.org URL."""
    parsed = urllib.parse.urlparse(value)
    if parsed.scheme != "https" or parsed.hostname != "upload.wikimedia.org":
        return None

    segments = [urllib.parse.unquote(segment) for segment in parsed.path.split("/") if segment]
    try:
        commons_index = segments.index("commons")
    except ValueError:
        return None

    tail = segments[commons_index + 1 :]
    if len(tail) >= 4 and tail[0] == "thumb":
        filename = tail[3]
    elif len(tail) >= 3:
        filename = tail[2]
    else:
        return None

    filename = filename.strip()
    if not filename or filename.startswith("."):
        return None
    return f"File:{filename}"


def clean_metadata_text(value: str | None) -> str:
    if not value:
        return ""
    without_tags = re.sub(r"<[^>]+>", " ", html.unescape(value))
    return " ".join(without_tags.split())


def is_allowed_license(short_name: str | None) -> bool:
    """Allow only licenses with simple redistribution terms for this intake."""
    normalized = clean_metadata_text(short_name).upper().replace("_", " ")
    normalized = " ".join(normalized.split())
    if not normalized:
        return False
    if "PUBLIC DOMAIN" in normalized or normalized == "PD" or normalized.startswith("PD-"):
        return True
    if normalized.startswith("CC0"):
        return True
    return bool(
        re.fullmatch(
            r"CC[ -]+BY(?:[ -]+SA)?(?:[ -]+\d+(?:\.\d+)?)?",
            normalized,
        )
    )


def load_discovered_files(paths: Iterable[Path]) -> list[DiscoveredFile]:
    grouped: dict[str, dict[str, set[str]]] = {}
    for path in paths:
        rows = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(rows, list):
            raise ValueError(f"{path}: expected a JSON array")
        for row in rows:
            if not isinstance(row, dict):
                continue
            image_url = str(row.get("imageUrl", ""))
            title = commons_title_from_url(image_url)
            if title is None:
                continue
            entry = grouped.setdefault(title, {"source_pages": set(), "thumbnail_urls": set()})
            source_page = str(row.get("scrapedFromUrl", "")).strip()
            if source_page:
                entry["source_pages"].add(source_page)
            entry["thumbnail_urls"].add(image_url)

    return [
        DiscoveredFile(
            title=title,
            source_pages=tuple(sorted(values["source_pages"])),
            thumbnail_urls=tuple(sorted(values["thumbnail_urls"])),
        )
        for title, values in sorted(grouped.items())
    ]


def _metadata_value(metadata: dict[str, Any], key: str) -> str:
    item = metadata.get(key, {})
    if not isinstance(item, dict):
        return ""
    return clean_metadata_text(str(item.get("value", "")))


def _title_key(title: str) -> str:
    return " ".join(title.replace("_", " ").split()).casefold()


def query_commons(
    discovered: list[DiscoveredFile],
    *,
    thumb_width: int,
    api_delay: float = 1.0,
    cache_path: Path | None = None,
) -> list[dict[str, Any]]:
    by_title = {_title_key(item.title): item for item in discovered}
    resolved = _load_jsonl(cache_path) if cache_path and cache_path.exists() else []
    resolved_keys = {_title_key(str(item.get("title", ""))) for item in resolved}
    pending = [item for item in discovered if _title_key(item.title) not in resolved_keys]
    if resolved:
        print(f"Resuming from {len(resolved)} cached Commons records", file=sys.stderr)

    for offset in range(0, len(pending), MAX_BATCH_SIZE):
        batch = pending[offset : offset + MAX_BATCH_SIZE]
        request_data = urllib.parse.urlencode({
            "action": "query",
            "format": "json",
            "formatversion": "2",
            "prop": "imageinfo",
            "iiprop": "url|mime|size|extmetadata",
            "iiurlwidth": str(thumb_width),
            "titles": "|".join(item.title for item in batch),
        }).encode("utf-8")
        request = urllib.request.Request(
            COMMONS_API,
            data=request_data,
            headers={"User-Agent": USER_AGENT},
            method="POST",
        )
        payload = _request_json_with_retry(request, api_delay=api_delay)

        pages = payload.get("query", {}).get("pages", [])
        batch_resolved: list[dict[str, Any]] = []
        for page in pages:
            title = str(page.get("title", ""))
            discovery = by_title.get(_title_key(title))
            imageinfo = page.get("imageinfo") or []
            if discovery is None or not imageinfo:
                continue
            info = imageinfo[0]
            metadata = info.get("extmetadata") or {}
            batch_resolved.append({
                "title": title,
                "source_pages": list(discovery.source_pages),
                "apify_thumbnail_urls": list(discovery.thumbnail_urls),
                "description_url": str(info.get("descriptionurl", "")),
                "original_url": str(info.get("url", "")),
                "download_url": str(info.get("thumburl") or info.get("url") or ""),
                "mime": str(info.get("thumbmime") or info.get("mime") or ""),
                "original_mime": str(info.get("mime", "")),
                "original_width": int(info.get("width") or 0),
                "original_height": int(info.get("height") or 0),
                "review_width": int(info.get("thumbwidth") or info.get("width") or 0),
                "review_height": int(info.get("thumbheight") or info.get("height") or 0),
                "license_short_name": _metadata_value(metadata, "LicenseShortName"),
                "license_url": _metadata_value(metadata, "LicenseUrl"),
                "artist": _metadata_value(metadata, "Artist"),
                "credit": _metadata_value(metadata, "Credit"),
                "attribution": _metadata_value(metadata, "Attribution"),
            })
        resolved.extend(batch_resolved)
        if cache_path:
            _append_jsonl(cache_path, batch_resolved)
        print(
            f"Resolved Commons metadata for {len(resolved)}/"
            f"{len(discovered)} files",
            file=sys.stderr,
        )
        if offset + len(batch) < len(pending) and api_delay > 0:
            time.sleep(api_delay)
    return sorted(resolved, key=lambda item: str(item.get("title", "")))


def _request_json_with_retry(
    request: urllib.request.Request,
    *,
    api_delay: float,
    max_attempts: int = 5,
) -> dict[str, Any]:
    for attempt in range(max_attempts):
        try:
            with urllib.request.urlopen(request, timeout=45) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if error.code not in {429, 502, 503, 504} or attempt + 1 == max_attempts:
                raise
            retry_after = error.headers.get("Retry-After", "")
            delay = float(retry_after) if retry_after.isdigit() else max(api_delay, 2 ** (attempt + 1))
            delay = min(delay, 30.0)
            print(
                f"Commons API returned HTTP {error.code}; retrying in {delay:g}s "
                f"({attempt + 2}/{max_attempts})",
                file=sys.stderr,
            )
            time.sleep(delay)
    raise RuntimeError("unreachable Commons retry state")


def rejection_reason(item: dict[str, Any], *, min_long_edge: int, min_short_edge: int) -> str | None:
    if not is_allowed_license(str(item.get("license_short_name", ""))):
        return "license_not_allowlisted"
    if str(item.get("mime", "")) not in ALLOWED_MIME_TYPES:
        return "unsupported_review_mime"
    width = int(item.get("original_width") or 0)
    height = int(item.get("original_height") or 0)
    if max(width, height) < min_long_edge or min(width, height) < min_short_edge:
        return "insufficient_resolution"
    if not str(item.get("download_url", "")).startswith("https://upload.wikimedia.org/"):
        return "invalid_download_url"
    return None


def select_balanced(items: Iterable[dict[str, Any]], limit: int) -> list[dict[str, Any]]:
    groups: dict[str, deque[dict[str, Any]]] = defaultdict(deque)
    for item in sorted(items, key=lambda candidate: str(candidate["title"])):
        source_pages = item.get("source_pages") or ["unknown"]
        groups[str(source_pages[0])].append(item)

    selected: list[dict[str, Any]] = []
    group_names = sorted(groups)
    while len(selected) < limit and group_names:
        next_round: list[str] = []
        for group_name in group_names:
            group = groups[group_name]
            if group and len(selected) < limit:
                selected.append(group.popleft())
            if group:
                next_round.append(group_name)
        group_names = next_round
    return selected


def _extension_for_mime(mime: str) -> str:
    return {
        "image/jpeg": ".jpg",
        "image/png": ".png",
        "image/webp": ".webp",
    }[mime]


def download_candidate(
    item: dict[str, Any],
    *,
    images_dir: Path,
    max_bytes: int,
    max_attempts: int = 5,
) -> tuple[Path, str, int]:
    request = urllib.request.Request(
        str(item["download_url"]),
        headers={"User-Agent": USER_AGENT},
    )
    temporary_path = images_dir / ".download-part"
    try:
        for attempt in range(max_attempts):
            digest = hashlib.sha256()
            size = 0
            try:
                with urllib.request.urlopen(request, timeout=60) as response, temporary_path.open("wb") as output:
                    while chunk := response.read(64 * 1024):
                        size += len(chunk)
                        if size > max_bytes:
                            raise ValueError(f"download exceeds {max_bytes} bytes")
                        digest.update(chunk)
                        output.write(chunk)
                sha256 = digest.hexdigest()
                destination = images_dir / f"commons-{sha256[:16]}{_extension_for_mime(str(item['mime']))}"
                if destination.exists():
                    temporary_path.unlink()
                else:
                    shutil.move(str(temporary_path), destination)
                return destination, sha256, size
            except urllib.error.HTTPError as error:
                temporary_path.unlink(missing_ok=True)
                if error.code not in {429, 502, 503, 504} or attempt + 1 == max_attempts:
                    raise
                retry_after = error.headers.get("Retry-After", "")
                delay = float(retry_after) if retry_after.isdigit() else 2 ** (attempt + 1)
                delay = min(max(delay, 2.0), 30.0)
                print(
                    f"Image download returned HTTP {error.code}; retrying in {delay:g}s "
                    f"({attempt + 2}/{max_attempts})",
                    file=sys.stderr,
                )
                time.sleep(delay)
        raise RuntimeError("unreachable image retry state")
    finally:
        temporary_path.unlink(missing_ok=True)


def import_candidates(args: argparse.Namespace) -> dict[str, Any]:
    discovered = load_discovered_files(args.inputs)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    resolved = query_commons(
        discovered,
        thumb_width=args.thumb_width,
        api_delay=args.api_delay,
        cache_path=args.output_dir / "resolved-commons.jsonl",
    )
    rejected: list[dict[str, Any]] = []
    eligible: list[dict[str, Any]] = []
    for item in resolved:
        reason = rejection_reason(
            item,
            min_long_edge=args.min_long_edge,
            min_short_edge=args.min_short_edge,
        )
        if reason:
            rejected.append({**item, "rejection_reason": reason})
        else:
            eligible.append(item)

    selected = select_balanced(eligible, args.limit)
    images_dir = args.output_dir / "images"
    images_dir.mkdir(exist_ok=True)

    candidates: list[dict[str, Any]] = []
    content_hashes: set[str] = set()
    for index, item in enumerate(selected, start=1):
        try:
            local_path, sha256, byte_count = download_candidate(
                item,
                images_dir=images_dir,
                max_bytes=args.max_bytes,
            )
        except (OSError, ValueError) as error:
            rejected.append({**item, "rejection_reason": f"download_failed: {error}"})
            continue
        finally:
            if index < len(selected) and args.download_delay > 0:
                time.sleep(args.download_delay)
        if sha256 in content_hashes:
            rejected.append({**item, "rejection_reason": "duplicate_content"})
            continue
        content_hashes.add(sha256)
        candidates.append({
            "schema_version": 1,
            "status": "candidate",
            "commons_title": item["title"],
            "local_image": str(local_path.relative_to(args.output_dir)),
            "image_sha256": sha256,
            "image_bytes": byte_count,
            "review_width": item["review_width"],
            "review_height": item["review_height"],
            "original_width": item["original_width"],
            "original_height": item["original_height"],
            "mime": item["mime"],
            "source_pages": item["source_pages"],
            "description_url": item["description_url"],
            "original_url": item["original_url"],
            "license_short_name": item["license_short_name"],
            "license_url": item["license_url"],
            "artist": item["artist"],
            "credit": item["credit"],
            "attribution": item["attribution"],
            "machine_license_allowlisted": True,
            "redistributable": False,
            "license_reviewed": False,
            "sanitized": False,
            "cloud_processing_authorized": False,
        })
        if index % 20 == 0 or index == len(selected):
            print(f"Downloaded {index}/{len(selected)} selected candidates", file=sys.stderr)

    _write_jsonl(args.output_dir / "candidates.jsonl", candidates)
    _write_jsonl(args.output_dir / "rejected.jsonl", rejected)
    summary = {
        "apify_metadata_files": len(args.inputs),
        "discovered_commons_files": len(discovered),
        "resolved_commons_files": len(resolved),
        "eligible_before_limit": len(eligible),
        "selected_for_download": len(selected),
        "downloaded_unique_candidates": len(candidates),
        "rejected_or_failed": len(rejected),
        "review_bytes": sum(int(item["image_bytes"]) for item in candidates),
        "machine_license_allowlisted": True,
        "redistributable": False,
        "license_reviewed": False,
        "sanitized": False,
        "cloud_processing_authorized": False,
        "benchmark_ready": False,
    }
    (args.output_dir / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return summary


def _write_jsonl(path: Path, rows: Iterable[dict[str, Any]]) -> None:
    with path.open("w", encoding="utf-8") as output:
        for row in rows:
            output.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n")


def _append_jsonl(path: Path, rows: Iterable[dict[str, Any]]) -> None:
    with path.open("a", encoding="utf-8") as output:
        for row in rows:
            output.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n")


def _load_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        try:
            row = json.loads(line)
        except json.JSONDecodeError as error:
            raise ValueError(f"{path}:{line_number}: invalid cached JSON: {error}") from error
        if not isinstance(row, dict):
            raise ValueError(f"{path}:{line_number}: cached row must be an object")
        rows.append(row)
    return rows


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Turn Apify Wikimedia image discovery metadata into review-only benchmark candidates."
    )
    parser.add_argument("inputs", type=Path, nargs="+", help="Apify output metadata JSON files")
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--limit", type=int, default=180)
    parser.add_argument("--thumb-width", type=int, default=1600)
    parser.add_argument("--api-delay", type=float, default=1.0)
    parser.add_argument("--download-delay", type=float, default=1.5)
    parser.add_argument("--min-long-edge", type=int, default=800)
    parser.add_argument("--min-short-edge", type=int, default=400)
    parser.add_argument("--max-bytes", type=int, default=10 * 1024 * 1024)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if (
        args.limit < 1
        or args.thumb_width < 1
        or args.max_bytes < 1
        or args.api_delay < 0
        or args.download_delay < 0
    ):
        print(
            "limit, thumb width, and max bytes must be positive; delays cannot be negative",
            file=sys.stderr,
        )
        return 64
    missing = [str(path) for path in args.inputs if not path.is_file()]
    if missing:
        print(f"missing input files: {', '.join(missing)}", file=sys.stderr)
        return 66
    try:
        summary = import_candidates(args)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"candidate import failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(summary, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
