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
  certificate_name="${SWIFTERPM_CERTIFICATE_NAME:-Developer ID Application: Tuist GmbH (U6LC622NKF)}"
  certificate_item="${SWIFTERPM_CERTIFICATE_ITEM:-op://swifterpm/Developer ID Application Certificate}"
  notary_key_item="${SWIFTERPM_NOTARY_KEY_ITEM:-op://swifterpm/App Store Connect API Key}"

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
  op_read_with_retry "App Store Connect API key" "${notary_key_item}/AuthKey.p8" --out-file "${stage_dir}/AuthKey.p8" >/dev/null
  notary_key_id="$(op_read_with_retry "App Store Connect API key ID" "${notary_key_item}/key-id")"
  notary_issuer="$(op_read_with_retry "App Store Connect API issuer" "${notary_key_item}/issuer-id")"
  ditto -c -k --keepParent "${stage_dir}/${bin_name}" "${notarization_zip}"
  xcrun notarytool submit "${notarization_zip}" \
    --wait \
    --key "${stage_dir}/AuthKey.p8" \
    --key-id "${notary_key_id}" \
    --issuer "${notary_issuer}" \
    --output-format json | jq -e '.status == "Accepted"' >/dev/null
fi

asset="swifterpm-${version}-${target}.tar.gz"
tar -C "${stage_dir}" -czf "dist/${asset}" "${bin_name}"
