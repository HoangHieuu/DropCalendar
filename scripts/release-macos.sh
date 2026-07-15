#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${SNAPCAL_RELEASE_VERSION:-${GITHUB_REF_NAME:-}}"
version="${version#v}"
build_number="${SNAPCAL_BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-}}"
output_dir="${SNAPCAL_RELEASE_OUTPUT_DIR:-${repo_root}/release-output}"
archive_path="${output_dir}/SnapCal.xcarchive"
export_dir="${output_dir}/export"
dmg_staging="${output_dir}/dmg"
dmg_path="${output_dir}/SnapCal-${version}.dmg"
derived_data="${repo_root}/.build/ReleaseDerivedData"
package_dir="${repo_root}/.build/SourcePackages"

required=(
  version
  build_number
  SNAPCAL_API_BASE_URL
  SNAPCAL_UPDATE_FEED_URL
  SNAPCAL_SPARKLE_PUBLIC_KEY
)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "${name} is required for a production release." >&2
    exit 64
  fi
done

if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] \
  || [[ ! "${build_number}" =~ ^[1-9][0-9]*$ ]]; then
  echo "Release version and monotonically increasing build number are invalid." >&2
  exit 64
fi

if [[ ! "${SNAPCAL_API_BASE_URL}" =~ ^https:// ]] \
  || [[ ! "${SNAPCAL_UPDATE_FEED_URL}" =~ ^https:// ]] \
  || [[ "${SNAPCAL_SPARKLE_PUBLIC_KEY}" == "UNCONFIGURED" ]]; then
  echo "Release API, update feed, and Sparkle public key must be production values." >&2
  exit 64
fi

rm -rf "${output_dir}"
mkdir -p "${output_dir}" "${export_dir}" "${dmg_staging}"

xcodebuild \
  -project "${repo_root}/SnapCal.xcodeproj" \
  -scheme SnapCal \
  -configuration Release \
  -archivePath "${archive_path}" \
  -derivedDataPath "${derived_data}" \
  -clonedSourcePackagesDirPath "${package_dir}" \
  -packageAuthorizationProvider netrc \
  -disableAutomaticPackageResolution \
  -onlyUsePackageVersionsFromResolvedFile \
  -allowProvisioningUpdates \
  SNAPCAL_API_BASE_URL="${SNAPCAL_API_BASE_URL}" \
  SNAPCAL_UPDATE_FEED_URL="${SNAPCAL_UPDATE_FEED_URL}" \
  SNAPCAL_SPARKLE_PUBLIC_KEY="${SNAPCAL_SPARKLE_PUBLIC_KEY}" \
  MARKETING_VERSION="${version}" \
  CURRENT_PROJECT_VERSION="${build_number}" \
  archive

xcodebuild \
  -exportArchive \
  -archivePath "${archive_path}" \
  -exportPath "${export_dir}" \
  -exportOptionsPlist "${repo_root}/config/ExportOptions-DeveloperID.plist" \
  -allowProvisioningUpdates

app_path="${export_dir}/SnapCal.app"
if [[ ! -d "${app_path}" ]]; then
  echo "SnapCal.app was not exported." >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "${app_path}"

ditto "${app_path}" "${dmg_staging}/SnapCal.app"
ln -s /Applications "${dmg_staging}/Applications"
hdiutil create \
  -volname SnapCal \
  -srcfolder "${dmg_staging}" \
  -ov \
  -format UDZO \
  "${dmg_path}"

codesign --force --timestamp \
  --sign "${SNAPCAL_DEVELOPER_IDENTITY:-Developer ID Application}" \
  "${dmg_path}"
codesign --verify --strict --verbose=2 "${dmg_path}"

if [[ -n "${SNAPCAL_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  xcrun notarytool submit "${dmg_path}" \
    --keychain-profile "${SNAPCAL_NOTARY_KEYCHAIN_PROFILE}" \
    --wait
elif [[ -n "${SNAPCAL_NOTARY_KEY_PATH:-}" ]] \
  && [[ -n "${SNAPCAL_NOTARY_KEY_ID:-}" ]] \
  && [[ -n "${SNAPCAL_NOTARY_ISSUER_ID:-}" ]]; then
  xcrun notarytool submit "${dmg_path}" \
    --key "${SNAPCAL_NOTARY_KEY_PATH}" \
    --key-id "${SNAPCAL_NOTARY_KEY_ID}" \
    --issuer "${SNAPCAL_NOTARY_ISSUER_ID}" \
    --wait
else
  echo "notarytool credentials are required; unsigned release output is not retained." >&2
  rm -f "${dmg_path}"
  exit 64
fi

xcrun stapler staple "${dmg_path}"
xcrun stapler validate "${dmg_path}"
spctl --assess --type open --context context:primary-signature --verbose=2 "${dmg_path}"

if [[ -z "${SNAPCAL_SPARKLE_PRIVATE_KEY:-}" ]] \
  || [[ -z "${SNAPCAL_DOWNLOAD_URL_PREFIX:-}" ]]; then
  echo "Sparkle private key and download prefix are required for a signed appcast." >&2
  exit 64
fi

sparkle_bin="$(find "${package_dir}/artifacts" -type f -path '*/bin/generate_appcast' -print -quit)"
if [[ -z "${sparkle_bin}" ]]; then
  echo "Sparkle generate_appcast was not resolved." >&2
  exit 1
fi

printf '%s' "${SNAPCAL_SPARKLE_PRIVATE_KEY}" \
  | "${sparkle_bin}" \
      --ed-key-file - \
      --download-url-prefix "${SNAPCAL_DOWNLOAD_URL_PREFIX%/}" \
      --maximum-versions 3 \
      --maximum-deltas 2 \
      --phased-rollout-interval 86400 \
      -o "${output_dir}/appcast.xml" \
      "${output_dir}"

shasum -a 256 "${dmg_path}" "${output_dir}/appcast.xml" \
  >"${output_dir}/SHA256SUMS"

echo "Release artifacts are in ${output_dir}."
