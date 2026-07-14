#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${SNAPCAL_UI_DERIVED_DATA_PATH:-${ROOT_DIR}/.build/DerivedDataUI}"

cd "${ROOT_DIR}"

exec xcodebuild test \
  -quiet \
  -project SnapCal.xcodeproj \
  -scheme SnapCalUISmoke \
  -destination 'platform=macOS' \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  SNAPCAL_APP_BUNDLE_IDENTIFIER=com.snapcal.app.uitesthost \
  -only-testing:SnapCalUITests \
  "$@"
