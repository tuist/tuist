#!/bin/bash
# Reads the per-VM payload that tart-kubelet stages at
# /Volumes/My Shared Files/env/{tuist.env,sa_token}, materializes
# the env file as /etc/tuist.env, and copies the SA token into
# /etc/tuist-sa-token so the launchd wrapper can source the env
# and the dispatch-poll loop can read the Bearer credential.
#
# Mirrors the pattern used by xcresult-processor's inject-env.sh —
# same transport (tart-kubelet --dir env:<host>:ro), same on-disk
# format (KEY=value, one per line), same shell-quoting handling
# for values that carry awkward bytes (`@` in URLs, `+` / `/` in
# base64, multi-line PEM bundles).

set -euo pipefail

ENV_FILE="/etc/tuist.env"
SA_TOKEN_FILE="/etc/tuist-sa-token"

# Always start from a clean file. Permissions allow the launchd-
# spawned user to read it; root owns it so an in-VM compromise of
# the daemon can't tamper with the file mid-run.
sudo install -m 0640 -o root -g admin /dev/null "${ENV_FILE}"
sudo install -m 0640 -o root -g admin /dev/null "${SA_TOKEN_FILE}"

ENV_SRC="/Volumes/My Shared Files/env/tuist.env"
TOKEN_SRC="/Volumes/My Shared Files/env/sa_token"

if [ ! -f "${ENV_SRC}" ]; then
  echo "inject-env: no env source at ${ENV_SRC}; runner won't be able to dispatch" >&2
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
  done < "${ENV_SRC}"
} | sudo tee "${ENV_FILE}" >/dev/null
echo "inject-env: wrote ${ENV_FILE} from ${ENV_SRC}"

if [ -f "${TOKEN_SRC}" ]; then
  sudo cp "${TOKEN_SRC}" "${SA_TOKEN_FILE}"
  sudo chown root:admin "${SA_TOKEN_FILE}"
  sudo chmod 0640 "${SA_TOKEN_FILE}"
  echo "inject-env: wrote ${SA_TOKEN_FILE} from ${TOKEN_SRC}"
else
  echo "inject-env: no SA token at ${TOKEN_SRC}; dispatch will fail at curl time"
fi
