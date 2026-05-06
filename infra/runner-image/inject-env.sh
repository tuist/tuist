#!/bin/bash
# Reads the per-VM env payload that tart-kubelet stages at
# /Volumes/My Shared Files/env/tuist.env into /etc/tuist.env so the
# launchd job's wrapper can `source` it before exec'ing the
# dispatch-poll loop.
#
# Mirrors the pattern used by xcresult-processor's inject-env.sh —
# same transport (tart-kubelet --dir env:<host>:ro), same on-disk
# format (KEY=value, one per line), same shell-quoting handling
# for values that carry awkward bytes (`@` in URLs, `+` / `/` in
# base64, multi-line PEM bundles).

set -euo pipefail

ENV_FILE="/etc/tuist.env"

# Always start from a clean file. Permissions allow the launchd-
# spawned user to read it; root owns it so an in-VM compromise of
# the daemon can't tamper with the file mid-run.
sudo install -m 0640 -o root -g admin /dev/null "${ENV_FILE}"

KUBELET_PATH="/Volumes/My Shared Files/env/tuist.env"

if [ ! -f "${KUBELET_PATH}" ]; then
  echo "inject-env: no env source at ${KUBELET_PATH}; runner won't be able to dispatch" >&2
  exit 0
fi

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
