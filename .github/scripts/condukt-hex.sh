#!/usr/bin/env bash
# Called only after the public native artifacts have been verified.
set -euo pipefail
: "${RELEASE_VERSION:?}" "${RUNNER_TEMP:?}"
package="condukt-$RELEASE_VERSION.tar"
test -s "$package"
status=$(curl --silent --show-error --location --output "$RUNNER_TEMP/condukt-hex.tar" \
  --write-out '%{http_code}' "https://repo.hex.pm/tarballs/$package")
case "$status" in
  200) cmp "$package" "$RUNNER_TEMP/condukt-hex.tar" ;;
  404) mix hex.publish package --yes ;;
  *) echo "Cannot determine Hex publication state (HTTP $status)" >&2; exit 1 ;;
esac
