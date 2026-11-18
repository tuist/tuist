#!/usr/bin/env bash
# Verify the resolved configuration, not merely the requested fragment.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
config=${1:?usage: check-config.sh <resolved-config>}
while IFS= read -r line; do
  case "$line" in
    CONFIG_*=*|'# CONFIG_'*' is not set')
      grep -Fxq "$line" "$config" || { echo "Required setting missing: $line" >&2; exit 1; }
      ;;
  esac
done < "$here/host.conf"
