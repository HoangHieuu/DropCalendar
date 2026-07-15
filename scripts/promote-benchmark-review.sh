#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $# -ne 4 ]]; then
  echo "Usage: scripts/promote-benchmark-review.sh <calibration|acceptance> <candidates.jsonl> <review-decisions.jsonl> <external-corpus-dir>" >&2
  exit 64
fi

profile="$1"
if [[ "${profile}" != "calibration" && "${profile}" != "acceptance" ]]; then
  echo "Profile must be calibration or acceptance." >&2
  exit 64
fi

PYTHONPATH="${repo_root}/packages/benchmark${PYTHONPATH:+:${PYTHONPATH}}" \
  python3 -m snapcal_benchmark.review_promotion promote \
    --profile "${profile}" \
    --candidates "$2" \
    --decisions "$3" \
    --output-dir "$4"
