#!/usr/bin/env bash
set -euo pipefail

architecture="$(uname -m)"
macos_version="$(sw_vers -productVersion)"
developer_dir="${DEVELOPER_DIR:-$(xcode-select -p)}"
xcode_bundle="${developer_dir%/Contents/Developer}"
sdk_path="${developer_dir}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
swift_bin="${developer_dir}/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
xcode_version="unknown"
sdk_version="unknown"

if [[ -f "${xcode_bundle}/Contents/Info.plist" ]]; then
  xcode_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${xcode_bundle}/Contents/Info.plist")"
fi
if [[ -f "${sdk_path}/SDKSettings.plist" ]]; then
  sdk_version="$(/usr/bin/plutil -extract Version raw "${sdk_path}/SDKSettings.plist")"
fi

if DEVELOPER_DIR="${developer_dir}" xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
  xcode_license_accepted=true
else
  xcode_license_accepted=false
fi

if [[ -x "${swift_bin}" ]] && [[ -d "${sdk_path}" ]] && \
  "${swift_bin}" -sdk "${sdk_path}" -e 'import FoundationModels' >/dev/null 2>&1; then
  module_available=true
else
  module_available=false
fi

runtime_availability="framework_unavailable"
supports_vietnamese=false
supports_english=false
if [[ "${module_available}" == true ]]; then
  runtime_probe="$("${swift_bin}" -sdk "${sdk_path}" -e '
    import Foundation
    import FoundationModels

    if #available(macOS 26.0, *) {
        let model = SystemLanguageModel.default
        let availability: String
        switch model.availability {
        case .available:
            availability = "available"
        case .unavailable(.deviceNotEligible):
            availability = "device_not_eligible"
        case .unavailable(.appleIntelligenceNotEnabled):
            availability = "apple_intelligence_not_enabled"
        case .unavailable(.modelNotReady):
            availability = "model_not_ready"
        @unknown default:
            availability = "unknown"
        }
        print(availability)
        print(model.supportsLocale(Locale(identifier: "vi_VN")))
        print(model.supportsLocale(Locale(identifier: "en_US")))
    } else {
        print("operating_system_unsupported")
        print(false)
        print(false)
    }
  ' 2>/dev/null || true)"
  runtime_availability="$(sed -n '1p' <<<"${runtime_probe}")"
  supports_vietnamese="$(sed -n '2p' <<<"${runtime_probe}")"
  supports_english="$(sed -n '3p' <<<"${runtime_probe}")"
  [[ "${supports_vietnamese}" == "true" ]] || supports_vietnamese=false
  [[ "${supports_english}" == "true" ]] || supports_english=false
  [[ -n "${runtime_availability}" ]] || runtime_availability="probe_failed"
fi

printf '{"architecture":"%s","foundation_models_module_available":%s,"foundation_models_runtime_availability":"%s","supports_english":%s,"supports_vietnamese":%s,"macos_version":"%s","macos_sdk_version":"%s","xcode_license_accepted":%s,"xcode_version":"%s"}\n' \
  "${architecture}" \
  "${module_available}" \
  "${runtime_availability}" \
  "${supports_english}" \
  "${supports_vietnamese}" \
  "${macos_version}" \
  "${sdk_version}" \
  "${xcode_license_accepted}" \
  "${xcode_version}"
