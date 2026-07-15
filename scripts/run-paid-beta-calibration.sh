#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="${repo_root}/.build/paid-beta-calibration"
manifest="${work_dir}/manifest.jsonl"
records="${work_dir}/cost-latency.jsonl"
report="${work_dir}/cost-latency-report.json"
python_bin="${SNAPCAL_BENCHMARK_PYTHON:-${repo_root}/.venv/bin/python}"

if [[ "${SNAPCAL_BENCHMARK_ALLOW_CLOUD:-0}" != "1" ]]; then
  echo "Calibration sends exactly 20 sanitized fixtures to OpenRouter." >&2
  echo "Set SNAPCAL_BENCHMARK_ALLOW_CLOUD=1 after confirming the dedicated key limit." >&2
  exit 64
fi

mkdir -p "${work_dir}"
rm -f "${work_dir}/images"
ln -s "${repo_root}/packages/benchmark/corpus/images" "${work_dir}/images"
sed -n '1,20p' "${repo_root}/packages/benchmark/corpus/manifest.jsonl" >"${manifest}"

SNAPCAL_BENCHMARK_PROFILE=calibration \
SNAPCAL_BENCHMARK_MANIFEST="${manifest}" \
SNAPCAL_BENCHMARK_BUDGET_USD="${SNAPCAL_BENCHMARK_BUDGET_USD:-0.25}" \
SNAPCAL_BENCHMARK_COST_RECORDS="${records}" \
  "${repo_root}/scripts/run-accuracy-benchmark.sh"

"${python_bin}" \
  "${repo_root}/packages/benchmark/tools/check_paid_beta_calibration.py" \
  "${records}" \
  "${report}"
