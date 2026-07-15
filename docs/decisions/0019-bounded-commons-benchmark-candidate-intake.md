# 0019 Bounded Commons Benchmark Candidate Intake

Date: 2026-07-15

## Status

Accepted

## Context

US-006 needs at least 100 licensed, sanitized, non-synthetic event images, but
arbitrary web scraping would make redistribution, attribution, privacy, and
provider-cost boundaries unclear. Apify can cheaply discover image URLs, while
its category-page output is limited to low-resolution thumbnails and is not a
license authority. Automatically promoting downloaded web images into the
benchmark would bypass the existing fail-closed review contract.

## Decision

- Use Apify only for bounded source discovery. Each actor run must have an
  explicit cost ceiling, and bulk collection stops well below the user's total
  account credit.
- For Wikimedia-hosted discoveries, resolve the canonical file, license,
  attribution, dimensions, and review URL through the Wikimedia Commons API.
- Accept into the candidate pool only public-domain, CC0, CC BY, or CC BY-SA
  metadata. Reject unclear, noncommercial, no-derivatives, unsupported-media,
  low-resolution, or non-Wikimedia download results.
- Identify and pace the Commons client, honor server cooldowns, cache resolved
  metadata, request a 1600-pixel target width, enforce a 10 MB hard byte cap,
  and retain SHA-256 evidence. Commons may return a nearby standardized
  thumbnail width.
- Keep candidates in an owner-controlled directory outside Git. Record the
  machine license allowlist result, but mark redistributability, license review,
  sanitization, and cloud-processing authorization false by default.
- Never generate a benchmark manifest row from acquisition or machine triage.
  Human review must establish event relevance, attribution, privacy safety,
  language, difficulty, ground truth, and any Accuracy Mode authorization. A
  fail-closed promotion tool may materialize a manifest only from explicitly
  approved review records with two distinct reviewers and all schema gates.

## Alternatives Considered

1. Use Apify's downloaded 120-pixel thumbnails directly. Rejected because they
   are too small and omit authoritative license/attribution metadata.
2. Scrape arbitrary image-search results. Rejected because rights, privacy, and
   provenance cannot be made fail-closed reliably.
3. Generate the entire corpus synthetically. Rejected for real-world acceptance;
   generated fixtures remain useful only for regression evidence.
4. Check candidates into Git immediately. Rejected because license and privacy
   review are not complete at acquisition time.

## Consequences

Positive:

- Acquisition volume is inexpensive and reproducible without weakening the
  benchmark's provenance or sanitization gates.
- Attribution and rejection evidence remain attached to each review candidate.
- Provider limits and user credit are bounded explicitly.

Tradeoffs:

- Commons categories contain historical material, photographs of posters,
  near-duplicates, and limited Vietnamese coverage, so manual review and
  additional Vietnamese-English sourcing are still required.
- Candidate acquisition does not by itself advance US-006 to implemented or
  support any accuracy claim.

## Follow-Up

- Review and label the 180 external candidates, removing non-events,
  duplicates, privacy risks, and attribution failures.
- Acquire enough Vietnamese or mixed-language images to satisfy the 50-item
  quota after review.
- Use the fail-closed promotion command to build an owner-controlled manifest
  only from approved items, then run both Local Only and explicitly authorized
  Accuracy Mode acceptance.
