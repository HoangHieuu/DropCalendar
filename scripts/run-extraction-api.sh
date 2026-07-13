#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -z "${GEMINI_API_KEY:-}" ]]; then
  echo "GEMINI_API_KEY is not set. Export a dedicated Gemini authorization key first." >&2
  exit 1
fi

HOST="${SNAPCAL_EXTRACTION_HOST:-127.0.0.1}"
PORT="${SNAPCAL_EXTRACTION_PORT:-8765}"
PYTHON_BIN="${SNAPCAL_PYTHON:-.venv/bin/python}"

if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "Python environment not found at $PYTHON_BIN. Create .venv and install services/extraction-api/requirements.txt first." >&2
  exit 1
fi

exec "$PYTHON_BIN" -m uvicorn app.main:app \
  --app-dir services/extraction-api \
  --host "$HOST" \
  --port "$PORT"
