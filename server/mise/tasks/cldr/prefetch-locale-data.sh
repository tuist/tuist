#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
CLDR_DATA_DIR="${TUIST_CLDR_DATA_DIR:-${SERVER_DIR}/_build/cldr/locales}"
LOCALES=(
  ar
  es
  ja
  ka
  ko
  pl
  pt
  ru
  tr
  yue-Hant
  zh-Hans
  zh-Hant
)

cd "${SERVER_DIR}"

cldr_version="$(sed -n 's/^  "ex_cldr": {:hex, :ex_cldr, "\([^"]*\)".*/\1/p' mix.lock)"
if [ -z "${cldr_version}" ]; then
  echo "Unable to determine ex_cldr version from mix.lock" >&2
  exit 1
fi

mkdir -p "${CLDR_DATA_DIR}"

for locale in "${LOCALES[@]}"; do
  output="${CLDR_DATA_DIR}/${locale}.json"
  if [ -s "${output}" ]; then
    continue
  fi

  tmp_output="${output}.tmp"
  rm -f "${tmp_output}"

  curl --fail --silent --show-error --location \
    --retry 5 \
    --retry-all-errors \
    --retry-delay 2 \
    -H "Accept: application/vnd.github.raw" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/elixir-cldr/cldr/contents/priv/cldr/locales/${locale}.json?ref=v${cldr_version}" \
    --output "${tmp_output}"

  mv "${tmp_output}" "${output}"
done
