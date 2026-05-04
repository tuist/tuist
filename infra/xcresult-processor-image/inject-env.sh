#!/bin/bash
# Reads the per-VM env payload into /etc/tuist.env so launchd's
# dev.tuist.xcresult-processor unit can source it. Runs once at boot.
#
# Transport: tart-kubelet stages the env file via `--dir env:<host>:ro`,
# which the guest sees at /Volumes/My Shared Files/env/tuist.env in
# plain `KEY=value` form (one per line, kubelet escapes embedded
# \n / \r). We re-emit it as `export KEY='value'` lines into
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

python3 - "${KUBELET_PATH}" "${ENV_FILE}" <<'PY'
import os, shlex, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src, "r") as f:
    lines = f.read().splitlines()
with open(dst, "w") as f:
    for line in lines:
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        # tart-kubelet writes literal `\n` / `\r` for embedded newlines.
        # Reverse that here so the BEAM sees the original byte sequence.
        value = value.replace("\\n", "\n").replace("\\r", "\r")
        f.write(f"export {key}={shlex.quote(value)}\n")
os.chmod(dst, 0o640)
PY
echo "inject-env: wrote ${ENV_FILE} from ${KUBELET_PATH}"
