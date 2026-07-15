#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python_bin="${SNAPCAL_BENCHMARK_PYTHON:-${repo_root}/.venv/bin/python}"
calibration_budget="${SNAPCAL_CALIBRATION_BUDGET_USD:-1.00}"
total_budget="5.00"

if [[ $# -ne 3 ]]; then
  echo "Usage: scripts/run-real-world-benchmark-pipeline.sh <20-item-calibration-manifest> <100+-item-acceptance-manifest> <external-output-dir>" >&2
  exit 64
fi

if [[ "${SNAPCAL_BENCHMARK_ALLOW_CLOUD:-0}" != "1" ]]; then
  echo "The real-world Accuracy pipeline is opt-in and sends authorized images to OpenRouter." >&2
  echo "Set SNAPCAL_BENCHMARK_ALLOW_CLOUD=1 only after reviewing both manifests and the dedicated \$5-limited key." >&2
  exit 64
fi

if [[ ! -x "${python_bin}" ]]; then
  echo "Python environment not found at ${python_bin}." >&2
  exit 1
fi

calibration_manifest="$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"
acceptance_manifest="$(cd "$(dirname "$2")" && pwd -P)/$(basename "$2")"
mkdir -p "$3"
output_root="$(cd "$3" && pwd -P)"

for private_path in "${calibration_manifest}" "${acceptance_manifest}" "${output_root}"; do
  case "${private_path}" in
    "${repo_root}"/*)
      echo "Real-world manifests, predictions, and item-level reports must remain outside the repository." >&2
      exit 65
      ;;
  esac
done

if [[ ! -f "${calibration_manifest}" || ! -f "${acceptance_manifest}" ]]; then
  echo "Both calibration and acceptance manifests must exist." >&2
  exit 66
fi

export PYTHONPATH="${repo_root}/packages/benchmark${PYTHONPATH:+:${PYTHONPATH}}"
source_revision="$(git -C "${repo_root}" rev-parse HEAD)"
calibration_count="$(awk 'NF { count += 1 } END { print count + 0 }' "${calibration_manifest}")"
acceptance_count="$(awk 'NF { count += 1 } END { print count + 0 }' "${acceptance_manifest}")"
freeze_path="${output_root}/acceptance-freeze.json"
projection_path="${output_root}/accuracy-cost-projection.json"
pipeline_metadata_path="${output_root}/accuracy-pipeline-metadata.json"

validate_private_manifest() {
  local manifest="$1"
  local profile_flag="$2"
  SNAPCAL_BENCHMARK_MANIFEST="${manifest}" \
    "${repo_root}/scripts/run-benchmark.sh" validate \
      "${profile_flag}" \
      --require-real-world \
      --require-cloud-authorized openrouter \
      --require-second-reviewed
}

run_local_profile() {
  local manifest="$1"
  local profile="$2"
  local profile_root="${output_root}/${profile}"
  SNAPCAL_BENCHMARK_MANIFEST="${manifest}" \
  SNAPCAL_BENCHMARK_RUNS_DIR="${profile_root}/runs" \
  SNAPCAL_BENCHMARK_REPORT_DIR="${profile_root}/reports" \
  SNAPCAL_BENCHMARK_REQUIRE_REAL_WORLD=1 \
  SNAPCAL_BENCHMARK_PROFILE="${profile}" \
    "${repo_root}/scripts/run-local-benchmark.sh"
}

run_accuracy_profile() {
  local manifest="$1"
  local profile="$2"
  local budget="$3"
  local profile_root="${output_root}/${profile}"
  SNAPCAL_BENCHMARK_MANIFEST="${manifest}" \
  SNAPCAL_BENCHMARK_RUNS_DIR="${profile_root}/runs" \
  SNAPCAL_BENCHMARK_REPORT_DIR="${profile_root}/reports" \
  SNAPCAL_BENCHMARK_REQUIRE_REAL_WORLD=1 \
  SNAPCAL_BENCHMARK_PROFILE="${profile}" \
  SNAPCAL_BENCHMARK_BUDGET_USD="${budget}" \
  SNAPCAL_BENCHMARK_SERVICE_LOG="${profile_root}/reports/accuracy-service.log" \
    "${repo_root}/scripts/run-accuracy-benchmark.sh"
}

# Fail before any OCR or network request if either private corpus is incomplete.
validate_private_manifest "${calibration_manifest}" --require-calibration
validate_private_manifest "${acceptance_manifest}" --require-complete

"${python_bin}" -m snapcal_benchmark.accuracy_pipeline freeze \
  --manifest "${acceptance_manifest}" \
  --item-count "${acceptance_count}" \
  --source-revision "${source_revision}" \
  --output "${freeze_path}"

# Local Only always runs first and cannot call the cloud or Calendar adapters.
run_local_profile "${calibration_manifest}" calibration
run_local_profile "${acceptance_manifest}" acceptance
"${python_bin}" -m snapcal_benchmark.accuracy_pipeline verify-freeze \
  --manifest "${acceptance_manifest}" \
  --freeze "${freeze_path}"

# Cloud calibration is capped independently before any acceptance request.
run_accuracy_profile "${calibration_manifest}" calibration "${calibration_budget}"

"${python_bin}" -m snapcal_benchmark.accuracy_pipeline project \
  --calibration-metadata "${output_root}/calibration/reports/accuracy-run-metadata.json" \
  --acceptance-item-count "${acceptance_count}" \
  --total-budget-usd "${total_budget}" \
  --output "${projection_path}"

acceptance_budget="$("${python_bin}" -c 'import json,sys; print(json.load(open(sys.argv[1]))["acceptance_budget_usd"])' "${projection_path}")"
"${python_bin}" -m snapcal_benchmark.accuracy_pipeline verify-freeze \
  --manifest "${acceptance_manifest}" \
  --freeze "${freeze_path}"
run_accuracy_profile "${acceptance_manifest}" acceptance "${acceptance_budget}"
"${python_bin}" -m snapcal_benchmark.accuracy_pipeline verify-freeze \
  --manifest "${acceptance_manifest}" \
  --freeze "${freeze_path}"

"${python_bin}" -m snapcal_benchmark.accuracy_pipeline finalize \
  --calibration-metadata "${output_root}/calibration/reports/accuracy-run-metadata.json" \
  --acceptance-metadata "${output_root}/acceptance/reports/accuracy-run-metadata.json" \
  --projection "${projection_path}" \
  --freeze "${freeze_path}" \
  --output "${pipeline_metadata_path}"

echo "Real-world Local Only and Accuracy reports completed under ${output_root}."
