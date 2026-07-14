#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec swift "${repo_root}/packages/benchmark/tools/GenerateSyntheticCorpus.swift"
