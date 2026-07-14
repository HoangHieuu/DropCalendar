#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_root="${repo_root}/.build/benchmark"
manifest="${SNAPCAL_BENCHMARK_MANIFEST:-${repo_root}/packages/benchmark/corpus/manifest.jsonl}"
runs_dir="${SNAPCAL_BENCHMARK_RUNS_DIR:-${repo_root}/packages/benchmark/runs}"
predictions="${runs_dir}/accuracy.jsonl"
runner="${build_root}/SnapCalAccuracyBenchmarkRunner"
base_url="${SNAPCAL_EXTRACTION_API_URL:-http://127.0.0.1:8765}"
validation_args=(--require-complete)

if [[ "${SNAPCAL_BENCHMARK_REQUIRE_REAL_WORLD:-0}" == "1" ]]; then
  validation_args+=(--require-real-world)
fi

if [[ "${SNAPCAL_BENCHMARK_ALLOW_CLOUD:-0}" != "1" ]]; then
  echo "Accuracy benchmark is opt-in and sends all corpus images to the configured OpenRouter-backed service." >&2
  echo "Set SNAPCAL_BENCHMARK_ALLOW_CLOUD=1 only after confirming provider cost and corpus disclosure." >&2
  exit 64
fi

"${repo_root}/scripts/run-benchmark.sh" validate "${validation_args[@]}"
mkdir -p "${build_root}" "$(dirname "${predictions}")"

swiftc -parse-as-library \
  -o "${runner}" \
  "${repo_root}/apps/macos/SnapCal/Domain/TrustPolicies.swift" \
  "${repo_root}/apps/macos/SnapCal/Domain/EventDraft.swift" \
  "${repo_root}/apps/macos/SnapCal/Domain/ExtractionMode.swift" \
  "${repo_root}/apps/macos/SnapCal/Domain/CalendarEvent.swift" \
  "${repo_root}/apps/macos/SnapCal/Infrastructure/ClipboardImageReader.swift" \
  "${repo_root}/apps/macos/SnapCal/Infrastructure/ImageValidator.swift" \
  "${repo_root}/apps/macos/SnapCal/Infrastructure/VisionOCRService.swift" \
  "${repo_root}/apps/macos/SnapCal/Infrastructure/HTTPTransport.swift" \
  "${repo_root}/apps/macos/SnapCal/Infrastructure/GeminiExtractionClient.swift" \
  "${repo_root}/packages/benchmark/tools/AccuracyBenchmarkRunner.swift" \
  -framework AppKit \
  -framework Vision

"${runner}" "${manifest}" "${predictions}" "${base_url%/}/v1/extract"
"${repo_root}/scripts/run-benchmark.sh" score \
  --mode accuracy \
  "${validation_args[@]}" \
  "$@"
