#!/usr/bin/env bash
set -euo pipefail

architecture="$(uname -m)"
macos_version="$(sw_vers -productVersion)"
xcode_version="$(xcodebuild -version | head -n 1 | awk '{print $2}')"
sdk_version="$(xcrun --sdk macosx --show-sdk-version)"

if swift -e 'import FoundationModels' >/dev/null 2>&1; then
  module_available=true
else
  module_available=false
fi

printf '{"architecture":"%s","foundation_models_module_available":%s,"macos_version":"%s","macos_sdk_version":"%s","xcode_version":"%s"}\n' \
  "${architecture}" \
  "${module_available}" \
  "${macos_version}" \
  "${sdk_version}" \
  "${xcode_version}"
