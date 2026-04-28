#!/bin/bash
# Reads Orchard's per-VM custom data into /etc/tuist.env so launchd's
# dev.tuist.xcresult-processor unit can source it. Runs once at boot.
#
# Custom data is JSON of the form:
#   {"env":{"MASTER_KEY":"...","DATABASE_URL":"postgres://...",...}}
#
# Tart exposes it through `softwareupdate --history` style metadata at a
# well-known path. We pull it via the `vmctl` helper Cirrus ships in their
# base macOS images; if absent, we fall back to no-op so the daemon fails
# loud with a missing-env error rather than silently using stale values.

set -euo pipefail

ENV_FILE="/etc/tuist.env"

# Always start from a clean file. Permissions allow the launchd-spawned
# user to read it; root owns it so an in-VM compromise of the daemon
# can't tamper with the file mid-run.
sudo install -m 0640 -o root -g admin /dev/null "${ENV_FILE}"

# Cirrus' macOS images expose Tart custom data at /Volumes/My Shared Files/
# (mounted by virtiofs) when started with `tart run --dir custom-data:...`,
# or via `vmctl` for user-data style payloads. The Orchard agent uses the
# user-data path via `tart run --user-data ...`.
USERDATA_PATH="/private/var/db/vmctl/user-data"

if [ ! -s "${USERDATA_PATH}" ]; then
  echo "inject-env: no user-data found at ${USERDATA_PATH}; daemon will fail with missing env" >&2
  exit 0
fi

# JSON shape: {"env":{"KEY":"VAL", ...}}. We don't pull jq into the image —
# /usr/bin/python3 ships with macOS — so use python's json module.
python3 - "${USERDATA_PATH}" "${ENV_FILE}" <<'PY'
import json, os, sys, shlex

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
        # launchd's EnvironmentVariables can't read this file directly; we
        # source it from a wrapper script. POSIX shell quoting protects
        # special chars in passwords / DB URLs.
        f.write(f"export {key}={shlex.quote(value)}\n")

os.chmod(dst, 0o640)
PY

echo "inject-env: wrote ${ENV_FILE}"
