#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_FILE="${PROJECT_FILE:-${SCRIPT_DIR}/../Turbodoc.xcodeproj/project.pbxproj}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/bump-version.sh [patch|minor|major|VERSION] [options]

Examples:
  ./scripts/bump-version.sh                 # 1.4 -> 1.4.1, build 5 -> 6
  ./scripts/bump-version.sh minor           # 1.4 -> 1.5.0, build 5 -> 6
  ./scripts/bump-version.sh 2.0             # Set version 2.0, build 5 -> 6
  ./scripts/bump-version.sh --build-only    # Keep version, build 5 -> 6
  ./scripts/bump-version.sh patch --dry-run # Preview without changing files

Options:
  --build NUMBER  Set an explicit build number instead of incrementing it
  --build-only    Increment only the build number
  --dry-run       Print the result without changing the project
  -h, --help      Show this help
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

unique_setting() {
  local setting="$1"
  local values

  values="$(
    sed -n "s/.*${setting} = \\([^;]*\\);/\\1/p" "${PROJECT_FILE}" |
      sort -u
  )"

  [[ -n "${values}" ]] || die "${setting} was not found in ${PROJECT_FILE}"
  [[ "$(printf '%s\n' "${values}" | wc -l | tr -d ' ')" == "1" ]] ||
    die "${setting} has inconsistent values: $(printf '%s' "${values}" | tr '\n' ' ')"

  printf '%s' "${values}"
}

bump_marketing_version() {
  local version="$1"
  local bump="$2"
  local major minor patch

  IFS='.' read -r major minor patch <<<"${version}"
  minor="${minor:-0}"
  patch="${patch:-0}"

  case "${bump}" in
    major) printf '%d.0.0' "$((10#${major} + 1))" ;;
    minor) printf '%d.%d.0' "$((10#${major}))" "$((10#${minor} + 1))" ;;
    patch) printf '%d.%d.%d' "$((10#${major}))" "$((10#${minor}))" "$((10#${patch} + 1))" ;;
    *) die "Unknown version bump: ${bump}" ;;
  esac
}

[[ -f "${PROJECT_FILE}" ]] || die "Xcode project not found at ${PROJECT_FILE}"

version_action="patch"
version_action_set=false
explicit_build=""
dry_run=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    patch | minor | major)
      [[ "${version_action_set}" == false ]] || die "Specify only one version action"
      version_action="$1"
      version_action_set=true
      ;;
    --build)
      [[ $# -ge 2 ]] || die "--build requires a number"
      explicit_build="$2"
      shift
      ;;
    --build-only)
      [[ "${version_action_set}" == false ]] || die "Specify only one version action"
      version_action="build-only"
      version_action_set=true
      ;;
    --dry-run)
      dry_run=true
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      [[ "${version_action_set}" == false ]] || die "Specify only one version action"
      version_action="$1"
      version_action_set=true
      ;;
  esac
  shift
done

current_version="$(unique_setting "MARKETING_VERSION")"
current_build="$(unique_setting "CURRENT_PROJECT_VERSION")"

[[ "${current_version}" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] ||
  die "Current marketing version is invalid: ${current_version}"
[[ "${current_build}" =~ ^[0-9]+$ ]] ||
  die "Current build number is invalid: ${current_build}"

case "${version_action}" in
  patch | minor | major)
    new_version="$(bump_marketing_version "${current_version}" "${version_action}")"
    ;;
  build-only)
    new_version="${current_version}"
    ;;
  *)
    [[ "${version_action}" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] ||
      die "Version must contain two or three numeric components (for example, 1.5 or 2.0.1)"
    new_version="${version_action}"
    ;;
esac

if [[ -n "${explicit_build}" ]]; then
  [[ "${explicit_build}" =~ ^[0-9]+$ ]] ||
    die "Build number must be a non-negative integer"
  new_build="${explicit_build}"
else
  new_build="$((10#${current_build} + 1))"
fi

if [[ "${new_version}" == "${current_version}" && "${new_build}" == "${current_build}" ]]; then
  die "The requested version and build are already set"
fi

echo "Marketing version: ${current_version} -> ${new_version}"
echo "Build number:      ${current_build} -> ${new_build}"

if [[ "${dry_run}" == true ]]; then
  echo "Dry run: no files changed."
  exit 0
fi

temporary_file="$(mktemp "${PROJECT_FILE}.XXXXXX")"
trap 'rm -f "${temporary_file}"' EXIT
cp -p "${PROJECT_FILE}" "${temporary_file}"

awk -v version="${new_version}" -v build="${new_build}" '
  /^[[:space:]]*MARKETING_VERSION = / {
    sub(/MARKETING_VERSION = [^;]+;/, "MARKETING_VERSION = " version ";")
  }
  /^[[:space:]]*CURRENT_PROJECT_VERSION = / {
    sub(/CURRENT_PROJECT_VERSION = [^;]+;/, "CURRENT_PROJECT_VERSION = " build ";")
  }
  { print }
' "${PROJECT_FILE}" >"${temporary_file}"

mv "${temporary_file}" "${PROJECT_FILE}"
trap - EXIT

[[ "$(unique_setting "MARKETING_VERSION")" == "${new_version}" ]] ||
  die "Failed to update marketing version"
[[ "$(unique_setting "CURRENT_PROJECT_VERSION")" == "${new_build}" ]] ||
  die "Failed to update build number"

echo "Updated ${PROJECT_FILE}"
