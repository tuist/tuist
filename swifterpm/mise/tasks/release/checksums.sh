#!/usr/bin/env bash
#MISE description="Generate SHA256.txt and SHA512.txt for release archives"
#USAGE flag "--dist <dist>" help="Directory containing release archives"
set -euo pipefail

dist=""
while (($# > 0)); do
  case "$1" in
    --dist)
      dist="${2}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${dist}" ]]; then
  echo "--dist is required" >&2
  exit 1
fi

archives=()
while IFS= read -r archive; do
  archives+=("${archive}")
done < <(find "${dist}" -maxdepth 1 -type f -name 'swifterpm-*.tar.gz' -print | sort)
if [[ "${#archives[@]}" -eq 0 ]]; then
  echo "no release archives found in ${dist}" >&2
  exit 1
fi

(
  cd "${dist}"
  rm -f SHA256.txt SHA512.txt
  for archive_path in "${archives[@]}"; do
    archive="$(basename "${archive_path}")"
    binary="$(tar -tzf "${archive}" | head -n 1)"
    if [[ -z "${binary}" ]]; then
      echo "archive ${archive} does not contain a binary" >&2
      exit 1
    fi
    if command -v sha256sum >/dev/null 2>&1; then
      sha256="$(tar -xOzf "${archive}" "${binary}" | sha256sum | awk '{print $1}')"
      sha512="$(tar -xOzf "${archive}" "${binary}" | sha512sum | awk '{print $1}')"
    else
      sha256="$(tar -xOzf "${archive}" "${binary}" | shasum -a 256 | awk '{print $1}')"
      sha512="$(tar -xOzf "${archive}" "${binary}" | shasum -a 512 | awk '{print $1}')"
    fi
    printf '%s  %s/%s\n' "${sha256}" "${archive}" "${binary}" >> SHA256.txt
    printf '%s  %s/%s\n' "${sha512}" "${archive}" "${binary}" >> SHA512.txt
  done
)
