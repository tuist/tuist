#!/bin/bash
# Reads the per-VM env payload into /etc/tuist.env so launchd's
# dev.tuist.xcresult-processor unit can source it. Runs once at boot.
#
# We support two transports:
#
#   1. tart-kubelet (`--dir env:<host-path>:ro`)  — the kubelet stages a
#      file at /Volumes/My Shared Files/env/tuist.env in plain
#      `KEY=value` form, one per line. This is the current architecture
#      where each Mac mini joins the cluster as a real Node and tart-
#      kubelet drives Tart locally.
#
#   2. Orchard / `tart run --user-data <file>` (legacy) — the host
#      writes a JSON payload `{"env":{"KEY":"VAL", ...}}` to
#      /private/var/db/vmctl/user-data. Tart 2.32 dropped the
#      `--user-data` flag, but Orchard's older tart still wires it up,
#      so we keep the path for backward compatibility.
#
# Both formats land in `/etc/tuist.env` as `export KEY='value'` lines so
# the wrapper bash launchd spawns can `source` it before exec'ing the
# Tuist release.

set -euo pipefail

ENV_FILE="/etc/tuist.env"

# Always start from a clean file. Permissions allow the launchd-spawned
# user to read it; root owns it so an in-VM compromise of the daemon
# can't tamper with the file mid-run.
sudo install -m 0640 -o root -g admin /dev/null "${ENV_FILE}"

KUBELET_PATH="/Volumes/My Shared Files/env/tuist.env"
ORCHARD_PATH="/private/var/db/vmctl/user-data"

if [ -f "${KUBELET_PATH}" ]; then
  # tart-kubelet --dir flow. KEY=value\n lines, no quoting (kubelet only
  # escapes \n / \r). Re-emit as `export KEY='value'` so source can
  # consume any password / URL safely.
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
  echo "inject-env: wrote ${ENV_FILE} from ${KUBELET_PATH} (tart-kubelet)"
  exit 0
fi

if [ -s "${ORCHARD_PATH}" ]; then
  # Legacy --user-data JSON flow. JSON shape:
  # {"env":{"KEY":"VAL", ...}}.
  python3 - "${ORCHARD_PATH}" "${ENV_FILE}" <<'PY'
import json, os, shlex, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src, "r") as f:
    payload = json.load(f)
env = payload.get("env", {})
if not isinstance(env, dict):
    raise SystemExit("inject-env: payload.env must be an object")
with open(dst, "w") as f:
    for key, value in env.items():
        if not isinstance(value, str):
            value = str(value)
        f.write(f"export {key}={shlex.quote(value)}\n")
os.chmod(dst, 0o640)
PY
  echo "inject-env: wrote ${ENV_FILE} from ${ORCHARD_PATH} (orchard --user-data)"
  exit 0
fi

echo "inject-env: no env source found at ${KUBELET_PATH} or ${ORCHARD_PATH}; daemon will fail with missing env" >&2
exit 0
