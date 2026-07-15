#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_root="${repo_root}/.build/benchmark"
runner="${build_root}/SnapCalCandidateOCRRunner"

if [[ $# -ne 2 ]]; then
  echo "Usage: scripts/triage-benchmark-candidates.sh <candidates.jsonl> <external-output-dir>" >&2
  exit 64
fi

candidates="$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"
mkdir -p "$2"
output_dir="$(cd "$2" && pwd -P)"

case "${candidates}" in
  "${repo_root}"/*)
    echo "Candidate manifests with private item metadata must remain outside the repository." >&2
    exit 65
    ;;
esac

case "${output_dir}" in
  "${repo_root}"/*)
    echo "OCR and review outputs must remain outside the repository." >&2
    exit 65
    ;;
esac

if [[ ! -f "${candidates}" ]]; then
  echo "Candidate manifest not found: ${candidates}" >&2
  exit 66
fi

mkdir -p "${build_root}"
swiftc -parse-as-library \
  -o "${runner}" \
  "${repo_root}/apps/macos/SnapCal/Infrastructure/VisionOCRService.swift" \
  "${repo_root}/packages/benchmark/tools/CandidateOCRRunner.swift" \
  -framework Vision \
  -framework ImageIO \
  -framework CryptoKit

ocr_results="${output_dir}/ocr-results.jsonl"
"${runner}" "${candidates}" "${ocr_results}"

PYTHONPATH="${repo_root}/packages/benchmark${PYTHONPATH:+:${PYTHONPATH}}" \
  python3 -m snapcal_benchmark.candidate_triage \
    --candidates "${candidates}" \
    --ocr-results "${ocr_results}" \
    --output-dir "${output_dir}"
