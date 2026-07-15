#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_root="${repo_root}/.build/benchmark"
manifest="${SNAPCAL_BENCHMARK_MANIFEST:-${repo_root}/packages/benchmark/corpus/manifest.jsonl}"
runs_dir="${SNAPCAL_BENCHMARK_RUNS_DIR:-${repo_root}/packages/benchmark/runs}"
report_dir="${SNAPCAL_BENCHMARK_REPORT_DIR:-${repo_root}/.build/benchmark}"
predictions="${runs_dir}/accuracy.jsonl"
runner="${build_root}/SnapCalAccuracyBenchmarkRunner"
cost_records="${SNAPCAL_BENCHMARK_COST_RECORDS:-}"
python_bin="${SNAPCAL_BENCHMARK_PYTHON:-${repo_root}/.venv/bin/python}"
budget_usd="${SNAPCAL_BENCHMARK_BUDGET_USD:-5.00}"
manage_service="${SNAPCAL_BENCHMARK_MANAGE_SERVICE:-1}"
preflight_report="${report_dir}/accuracy-preflight.json"
usage_report="${report_dir}/accuracy-usage.json"
score_report="${report_dir}/report-accuracy.json"
run_metadata="${report_dir}/accuracy-run-metadata.json"
service_log="${SNAPCAL_BENCHMARK_SERVICE_LOG:-${build_root}/accuracy-service.log}"
profile="${SNAPCAL_BENCHMARK_PROFILE:-acceptance}"
service_pid=""

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

cleanup() {
  if [[ -n "${service_pid}" ]] && kill -0 "${service_pid}" 2>/dev/null; then
    kill "${service_pid}" 2>/dev/null || true
    wait "${service_pid}" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

if [[ "${SNAPCAL_BENCHMARK_REQUIRE_REAL_WORLD:-0}" == "1" ]]; then
  validation_args+=(
    --require-real-world
    --require-cloud-authorized openrouter
    --require-second-reviewed
  )
fi

if [[ "${SNAPCAL_BENCHMARK_ALLOW_CLOUD:-0}" != "1" ]]; then
  echo "Accuracy benchmark is opt-in and sends all corpus images to the configured OpenRouter-backed service." >&2
  echo "Set SNAPCAL_BENCHMARK_ALLOW_CLOUD=1 only after confirming provider cost and corpus disclosure." >&2
  exit 64
fi

"${repo_root}/scripts/run-benchmark.sh" validate "${validation_args[@]}"
mkdir -p "${build_root}" "$(dirname "${predictions}")" "${report_dir}" "$(dirname "${service_log}")"

if [[ ! -x "${python_bin}" ]]; then
  echo "Python environment not found at ${python_bin}." >&2
  exit 1
fi

if [[ "${manage_service}" == "1" ]]; then
  benchmark_port="${SNAPCAL_BENCHMARK_PORT:-$("${python_bin}" -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')}"
  base_url="http://127.0.0.1:${benchmark_port}"
  SNAPCAL_BENCHMARK_MODE=1 \
  SNAPCAL_BENCHMARK_BUDGET_USD="${budget_usd}" \
  SNAPCAL_EXTRACTION_HOST=127.0.0.1 \
  SNAPCAL_EXTRACTION_PORT="${benchmark_port}" \
    "${repo_root}/scripts/run-extraction-api.sh" >"${service_log}" 2>&1 &
  service_pid=$!

  service_ready=0
  for _ in {1..60}; do
    if curl -fsS "${base_url}/health" >/dev/null 2>&1; then
      service_ready=1
      break
    fi
    if ! kill -0 "${service_pid}" 2>/dev/null; then
      break
    fi
    sleep 0.5
  done
  if [[ "${service_ready}" != "1" ]]; then
    echo "Dedicated Accuracy benchmark service did not become ready. See ${service_log}." >&2
    exit 1
  fi
elif [[ "${manage_service}" == "0" ]]; then
  base_url="${SNAPCAL_EXTRACTION_API_URL:-}"
  if [[ -z "${base_url}" ]]; then
    echo "Set SNAPCAL_EXTRACTION_API_URL when SNAPCAL_BENCHMARK_MANAGE_SERVICE=0." >&2
    exit 64
  fi
else
  echo "SNAPCAL_BENCHMARK_MANAGE_SERVICE must be 0 or 1." >&2
  exit 64
fi

if ! curl -fsS "${base_url%/}/v1/benchmark/preflight" -o "${preflight_report}"; then
  echo "Benchmark preflight failed. Use a dedicated OpenRouter key with a limit at or below $5." >&2
  exit 1
fi

swiftc -parse-as-library \
  -o "${runner}" \
  "${repo_root}/apps/macos/SnapCal/Domain/TrustPolicies.swift" \
  "${repo_root}/apps/macos/SnapCal/Domain/EventDraft.swift" \
  "${repo_root}/apps/macos/SnapCal/Domain/Account.swift" \
  "${repo_root}/apps/macos/SnapCal/Domain/ExtractionMode.swift" \
  "${repo_root}/apps/macos/SnapCal/Domain/CalendarEvent.swift" \
  "${repo_root}/apps/macos/SnapCal/Infrastructure/ClipboardImageReader.swift" \
  "${repo_root}/apps/macos/SnapCal/Infrastructure/ImageValidator.swift" \
  "${repo_root}/apps/macos/SnapCal/Infrastructure/VisionOCRService.swift" \
  "${repo_root}/apps/macos/SnapCal/Infrastructure/HTTPTransport.swift" \
  "${repo_root}/apps/macos/SnapCal/Infrastructure/AccuracyImagePreprocessor.swift" \
  "${repo_root}/apps/macos/SnapCal/Infrastructure/GeminiExtractionClient.swift" \
  "${repo_root}/packages/benchmark/tools/AccuracyBenchmarkRunner.swift" \
  -framework AppKit \
  -framework Vision

set +e
runner_arguments=("${manifest}" "${predictions}" "${base_url%/}/v1/benchmark/extract")
if [[ -n "${cost_records}" ]]; then
  runner_arguments+=("${cost_records}")
fi
"${runner}" "${runner_arguments[@]}"
runner_exit=$?
set -e

curl -fsS "${base_url%/}/v1/benchmark/status" -o "${usage_report}"
source_revision="$(git -C "${repo_root}" rev-parse HEAD)"

if [[ "${runner_exit}" -ne 0 ]]; then
  expected_item_count="$(awk 'NF { count += 1 } END { print count + 0 }' "${manifest}")"
  PYTHONPATH="${repo_root}/packages/benchmark${PYTHONPATH:+:${PYTHONPATH}}" \
    "${python_bin}" -m snapcal_benchmark.run_metadata \
      --manifest "${manifest}" \
      --preflight "${preflight_report}" \
      --status "${usage_report}" \
      --expected-item-count "${expected_item_count}" \
      --abort-reason "runner_exit_${runner_exit}" \
      --source-revision "${source_revision}" \
      --profile "${profile}" \
      --output "${run_metadata}"
  exit "${runner_exit}"
fi

set +e
score_gate_args=()
if [[ "${profile}" != "calibration" ]]; then
  score_gate_args+=(--enforce-gates)
fi
"${repo_root}/scripts/run-benchmark.sh" score \
  --mode accuracy \
  "${validation_args[@]}" \
  "${score_gate_args[@]}" \
  "$@"
score_exit=$?
set -e

PYTHONPATH="${repo_root}/packages/benchmark${PYTHONPATH:+:${PYTHONPATH}}" \
  "${python_bin}" -m snapcal_benchmark.run_metadata \
    --manifest "${manifest}" \
    --preflight "${preflight_report}" \
    --status "${usage_report}" \
    --score-report "${score_report}" \
    --source-revision "${source_revision}" \
    --profile "${profile}" \
    --output "${run_metadata}"

exit "${score_exit}"
