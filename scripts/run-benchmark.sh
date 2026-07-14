#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python_bin="${SNAPCAL_BENCHMARK_PYTHON:-${repo_root}/.venv/bin/python}"
manifest="${SNAPCAL_BENCHMARK_MANIFEST:-${repo_root}/packages/benchmark/corpus/manifest.jsonl}"
runs_dir="${SNAPCAL_BENCHMARK_RUNS_DIR:-${repo_root}/packages/benchmark/runs}"
report_dir="${SNAPCAL_BENCHMARK_REPORT_DIR:-${repo_root}/.build/benchmark}"

if [[ ! -x "${python_bin}" ]]; then
  python_bin="$(command -v python3)"
fi

export PYTHONPATH="${repo_root}/packages/benchmark${PYTHONPATH:+:${PYTHONPATH}}"

if [[ "${1:-}" == "score" ]]; then
  shift
  mode=""
  forwarded=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode)
        mode="${2:-}"
        forwarded+=("$1" "$mode")
        shift 2
        ;;
      *)
        forwarded+=("$1")
        shift
        ;;
    esac
  done
  if [[ -z "${mode}" ]]; then
    echo "score requires --mode local_only or --mode accuracy" >&2
    exit 64
  fi
  exec "${python_bin}" -m snapcal_benchmark score \
    --manifest "${manifest}" \
    --predictions "${runs_dir}/${mode}.jsonl" \
    --output "${report_dir}/report-${mode}.json" \
    "${forwarded[@]}"
fi

exec "${python_bin}" -m snapcal_benchmark "$@" \
  --manifest "${manifest}"
