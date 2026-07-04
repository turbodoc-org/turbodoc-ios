#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PROJECT_PATH="${PROJECT_PATH:-${PROJECT_ROOT}/Turbodoc.xcodeproj}"
SCHEME="${SCHEME:-Turbodoc}"
CONFIGURATION="Release"
TEAM_ID="${TEAM_ID:-7NA9PJ7WYB}"

timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"
archive_path="${ARCHIVE_PATH:-${PROJECT_ROOT}/build/Turbodoc-${timestamp}.xcarchive}"
export_path="${EXPORT_PATH:-${PROJECT_ROOT}/build/AppStore}"
upload=false

usage() {
  cat <<'EOF'
Build and archive Turbodoc with the Release configuration.

Usage:
  ./scripts/archive-release.sh [options]

Options:
  --upload                Upload the archive to App Store Connect
  --archive-path PATH     Override the output .xcarchive path
  --export-path PATH      Override the App Store export output directory
  -h, --help              Show this help

Environment overrides:
  PROJECT_PATH            Xcode project path
  SCHEME                  Shared Xcode scheme (default: Turbodoc)
  TEAM_ID                 Apple Developer team ID
  ARCHIVE_PATH            Output .xcarchive path
  EXPORT_PATH             App Store export output directory

Optional App Store Connect API key authentication:
  ASC_KEY_ID              App Store Connect API key ID
  ASC_ISSUER_ID           App Store Connect API issuer ID
  ASC_KEY_PATH            Path to the AuthKey_<KEY_ID>.p8 file

Without API key variables, --upload uses the Apple account configured in Xcode.
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --upload)
      upload=true
      ;;
    --archive-path)
      [[ $# -ge 2 ]] || die "--archive-path requires a path"
      archive_path="$2"
      shift
      ;;
    --export-path)
      [[ $# -ge 2 ]] || die "--export-path requires a path"
      export_path="$2"
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
  shift
done

command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild is not available"
[[ -d "${PROJECT_PATH}" ]] || die "Xcode project not found at ${PROJECT_PATH}"
[[ "${archive_path}" == *.xcarchive ]] ||
  die "Archive path must end in .xcarchive"

auth_values=("${ASC_KEY_ID:-}" "${ASC_ISSUER_ID:-}" "${ASC_KEY_PATH:-}")
auth_count=0
for value in "${auth_values[@]}"; do
  [[ -n "${value}" ]] && auth_count=$((auth_count + 1))
done

if [[ "${auth_count}" -ne 0 && "${auth_count}" -ne 3 ]]; then
  die "Set ASC_KEY_ID, ASC_ISSUER_ID, and ASC_KEY_PATH together"
fi
if [[ "${auth_count}" -eq 3 && ! -f "${ASC_KEY_PATH}" ]]; then
  die "App Store Connect API key not found at ${ASC_KEY_PATH}"
fi

mkdir -p "$(dirname "${archive_path}")"

echo "Archiving ${SCHEME} (${CONFIGURATION})"
echo "Archive path: ${archive_path}"

archive_args=(
  -project "${PROJECT_PATH}"
  -scheme "${SCHEME}"
  -configuration "${CONFIGURATION}"
  -destination "generic/platform=iOS"
  -archivePath "${archive_path}"
  -allowProvisioningUpdates
)
if [[ "${auth_count}" -eq 3 ]]; then
  archive_args+=(
    -authenticationKeyPath "${ASC_KEY_PATH}"
    -authenticationKeyID "${ASC_KEY_ID}"
    -authenticationKeyIssuerID "${ASC_ISSUER_ID}"
  )
fi
archive_args+=(archive)

xcodebuild "${archive_args[@]}"

echo "Archive created: ${archive_path}"

if [[ "${upload}" == false ]]; then
  echo "Run this script again with --upload to upload an archive to App Store Connect."
  exit 0
fi

mkdir -p "${export_path}"
export_options="$(mktemp "${TMPDIR:-/tmp}/Turbodoc-ExportOptions.XXXXXX")"
trap 'rm -f "${export_options}"' EXIT

cat >"${export_options}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>destination</key>
    <string>upload</string>
    <key>manageAppVersionAndBuildNumber</key>
    <false/>
    <key>method</key>
    <string>app-store-connect</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
EOF

echo "Uploading archive to App Store Connect"

export_args=(
  -exportArchive
  -archivePath "${archive_path}"
  -exportPath "${export_path}"
  -exportOptionsPlist "${export_options}"
  -allowProvisioningUpdates
)
if [[ "${auth_count}" -eq 3 ]]; then
  export_args+=(
    -authenticationKeyPath "${ASC_KEY_PATH}"
    -authenticationKeyID "${ASC_KEY_ID}"
    -authenticationKeyIssuerID "${ASC_ISSUER_ID}"
  )
fi

xcodebuild "${export_args[@]}"

echo "Upload completed successfully."
