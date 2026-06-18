#!/usr/bin/env bash
#MISE description="Build and package a release archive for a target triple"
#USAGE flag "--target <target>" help="Target triple to include in the release asset name"
#USAGE flag "--version <version>" help="Version number to embed in the asset name"
set -euo pipefail

target=""
version=""
while (($# > 0)); do
  case "$1" in
    --target)
      target="${2}"
      shift 2
      ;;
    --version)
      version="${2}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${target}" || -z "${version}" ]]; then
  echo "--target and --version are required" >&2
  exit 1
fi

mask_ci_value() {
  if [[ -n "${GITHUB_ACTIONS:-}" && -n "${1:-}" ]]; then
    printf "::add-mask::%s\n" "$1"
  fi
}

op_read_with_retry() {
  local description="$1"
  shift
  local max_attempts="${SWIFTERPM_OP_READ_ATTEMPTS:-5}"
  local delay_seconds="${SWIFTERPM_OP_READ_DELAY_SECONDS:-10}"
  local attempt=1

  while true; do
    if op read "$@"; then
      return 0
    fi

    local status=$?
    if ((attempt >= max_attempts)); then
      return "${status}"
    fi

    echo "op read failed for ${description}; retrying in ${delay_seconds}s (${attempt}/${max_attempts})" >&2
    sleep "${delay_seconds}"
    attempt=$((attempt + 1))
    delay_seconds=$((delay_seconds * 2))
  done
}

mkdir -p dist

case "${target}" in
  *-windows-*)
    bin_name="swifterpm.exe"
    ;;
  *)
    bin_name="swifterpm"
    ;;
esac

stage_dir="$(mktemp -d)"
trap 'rm -rf "${stage_dir}"' EXIT

case "${target}" in
  x86_64-unknown-linux-gnu)
    if command -v swift >/dev/null 2>&1; then
      swift build -c release --product swifterpm
      cp ".build/release/swifterpm" "${stage_dir}/${bin_name}"
    else
      docker run --rm \
        -v "${PWD}:/workspace" \
        -v "${stage_dir}:/stage" \
        -w /workspace \
        swift:6.1 \
        bash -lc "swift build -c release --product swifterpm && cp .build/release/swifterpm /stage/${bin_name}"
    fi
    ;;
  *)
    bazel build //:swifterpm
    cp "bazel-bin/swifterpm" "${stage_dir}/${bin_name}"
    ;;
esac

if [[ "${target}" == *-apple-darwin && "${SWIFTERPM_SIGN_MACOS:-}" == "true" ]]; then
  keychain_path="${stage_dir}/signing.keychain"
  keychain_password="$(uuidgen)"
  mask_ci_value "${keychain_password}"
  team_id="${SWIFTERPM_APPLE_TEAM_ID:-U6LC622NKF}"
  certificate_name="${SWIFTERPM_CERTIFICATE_NAME:-Developer ID Application: Tuist GmbH (U6LC622NKF)}"
  certificate_item="${SWIFTERPM_CERTIFICATE_ITEM:-op://swifterpm/Developer ID Application Certificate}"
  app_password_item="${SWIFTERPM_APP_PASSWORD_ITEM:-op://swifterpm/App Specific Password}"

  if [[ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]]; then
    echo "OP_SERVICE_ACCOUNT_TOKEN is required to sign and notarize macOS releases" >&2
    exit 1
  fi

  for tool in op security codesign xcrun ditto jq; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
      echo "${tool} is required to sign and notarize macOS releases" >&2
      exit 1
    fi
  done

  mask_ci_value "${OP_SERVICE_ACCOUNT_TOKEN}"

  echo "Setting up temporary keychain for macOS signing"
  security create-keychain -p "${keychain_password}" "${keychain_path}"
  security set-keychain-settings -lut 21600 "${keychain_path}"
  security default-keychain -s "${keychain_path}"
  security unlock-keychain -p "${keychain_password}" "${keychain_path}"
  security list-keychains -d user -s "${keychain_path}"

  op_read_with_retry "Developer ID certificate" "${certificate_item}/certificate.p12" --out-file "${stage_dir}/certificate.p12" >/dev/null
  certificate_password="$(op_read_with_retry "Developer ID certificate password" "${certificate_item}/password")"
  mask_ci_value "${certificate_password}"
  security import "${stage_dir}/certificate.p12" \
    -k "${keychain_path}" \
    -P "${certificate_password}" \
    -T /usr/bin/codesign \
    -T /usr/bin/security
  security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "${keychain_password}" \
    "${keychain_path}" >/dev/null

  echo "Signing ${bin_name}"
  codesign \
    --force \
    --timestamp \
    --options runtime \
    --sign "${certificate_name}" \
    "${stage_dir}/${bin_name}"

  echo "Submitting ${bin_name} for notarization"
  notarization_zip="${stage_dir}/notarization.zip"
  notary_username="$(op_read_with_retry "Apple notarization username" "${app_password_item}/username")"
  notary_password="$(op_read_with_retry "Apple notarization password" "${app_password_item}/password")"
  mask_ci_value "${notary_username}"
  mask_ci_value "${notary_password}"
  ditto -c -k --keepParent "${stage_dir}/${bin_name}" "${notarization_zip}"
  xcrun notarytool submit "${notarization_zip}" \
    --wait \
    --apple-id "${notary_username}" \
    --team-id "${team_id}" \
    --password "${notary_password}" \
    --output-format json | jq -e '.status == "Accepted"' >/dev/null
fi

asset="swifterpm-${version}-${target}.tar.gz"
tar -C "${stage_dir}" -czf "dist/${asset}" "${bin_name}"
