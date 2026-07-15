#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $# -lt 3 || $# -gt 4 ]]; then
  echo "Usage: scripts/prepare-benchmark-review.sh <candidates.jsonl> <review-queue.jsonl> <external-decisions.jsonl> [--likely-only]" >&2
  exit 64
fi

args=(
  template
  --candidates "$1"
  --review-queue "$2"
  --output "$3"
)
if [[ $# -eq 4 ]]; then
  if [[ "$4" != "--likely-only" ]]; then
    echo "Unknown option: $4" >&2
    exit 64
  fi
  args+=(--likely-only)
fi

PYTHONPATH="${repo_root}/packages/benchmark${PYTHONPATH:+:${PYTHONPATH}}" \
  python3 -m snapcal_benchmark.review_promotion "${args[@]}"
