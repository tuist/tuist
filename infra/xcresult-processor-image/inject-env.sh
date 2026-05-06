#!/bin/bash
# Reads the per-VM env payload into /etc/tuist.env so launchd's
# dev.tuist.xcresult-processor unit can source it. Runs once at boot.
#
# Transport: tart-kubelet stages the env file via `--dir env:<host>:ro`,
# which the guest sees at /Volumes/My Shared Files/env/tuist.env in
# plain `KEY=value` form (one per line, kubelet escapes embedded
# \n / \r). We re-emit it as `export KEY=<shell-quoted>` lines into
# /etc/tuist.env so the wrapper bash launchd spawns can `source` it
# before exec'ing the Tuist release.

set -euo pipefail

ENV_FILE="/etc/tuist.env"

# Always start from a clean file. Permissions allow the launchd-spawned
# user to read it; root owns it so an in-VM compromise of the daemon
# can't tamper with the file mid-run.
sudo install -m 0640 -o root -g admin /dev/null "${ENV_FILE}"

KUBELET_PATH="/Volumes/My Shared Files/env/tuist.env"

if [ ! -f "${KUBELET_PATH}" ]; then
  echo "inject-env: no env source at ${KUBELET_PATH}; daemon will fail with missing env" >&2
  exit 0
fi

# Each line is `KEY=value`. tart-kubelet writes \n / \r as two-character
# escapes to keep each var a single line on disk; reverse them so the
# BEAM sees the original bytes. `printf %q` then handles shell-quoting
# for any byte sequence the value might carry (Postgres URLs with `@`,
# S3 secrets with `+/`, multi-line CA bundles, etc.).
#
# `read … || [ -n "$line" ]` keeps the loop going for a final line
# without a trailing newline.
{
  while IFS= read -r line || [ -n "$line" ]; do
    [[ -z "$line" || "$line" == \#* || "$line" != *=* ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    value="${value//\\n/$'\n'}"
    value="${value//\\r/$'\r'}"
    printf 'export %s=%q\n' "$key" "$value"
  done < "${KUBELET_PATH}"
} | sudo tee "${ENV_FILE}" >/dev/null
echo "inject-env: wrote ${ENV_FILE} from ${KUBELET_PATH}"
