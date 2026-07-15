#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_root="${repo_root}/.build/benchmark"
manifest="${SNAPCAL_BENCHMARK_MANIFEST:-${repo_root}/packages/benchmark/corpus/manifest.jsonl}"
runs_dir="${SNAPCAL_BENCHMARK_RUNS_DIR:-${repo_root}/packages/benchmark/runs}"
predictions="${runs_dir}/local_only.jsonl"
runner="${build_root}/SnapCalLocalBenchmarkRunner"
profile="${SNAPCAL_BENCHMARK_PROFILE:-acceptance}"

case "${profile}" in
  calibration)
    validation_args=(--require-calibration)
    ;;
  acceptance|regression)
    validation_args=(--require-complete)
    ;;
  *)
    echo "SNAPCAL_BENCHMARK_PROFILE must be calibration, acceptance, or regression." >&2
    exit 64
    ;;
esac

if [[ "${SNAPCAL_BENCHMARK_REQUIRE_REAL_WORLD:-0}" == "1" ]]; then
  validation_args+=(--require-real-world --require-second-reviewed)
fi

"${repo_root}/scripts/run-benchmark.sh" validate "${validation_args[@]}"
mkdir -p "${build_root}" "$(dirname "${predictions}")"

swiftc -parse-as-library \
  -o "${runner}" \
  "${repo_root}/apps/macos/SnapCal/Domain/TrustPolicies.swift" \
  "${repo_root}/apps/macos/SnapCal/Domain/EventDraft.swift" \
  "${repo_root}/apps/macos/SnapCal/Infrastructure/VisionOCRService.swift" \
  "${repo_root}/apps/macos/SnapCal/Infrastructure/LocalEventExtractor.swift" \
  "${repo_root}/packages/benchmark/tools/LocalBenchmarkRunner.swift" \
  -framework AppKit \
  -framework Vision

"${runner}" "${manifest}" "${predictions}"
"${repo_root}/scripts/run-benchmark.sh" score \
  --mode local_only \
  "${validation_args[@]}" \
  "$@"
