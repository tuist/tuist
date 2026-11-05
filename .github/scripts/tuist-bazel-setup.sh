#!/usr/bin/env bash
# Configures the Tuist remote cache for the Bazel workspace in the current directory and, when the
# account has Linux remote execution capacity, the remote executor too. Without capacity (flag off,
# no worker with a ready template, no cache) the workspace stays cache-only, so a merge never waits
# on remote execution being available.
set -euo pipefail

tuist auth login
tuist bazel setup

server_url="${TUIST_URL:-https://tuist.dev}"
project="$(sed -n 's/^project = "\(.*\)"$/\1/p' tuist.toml)"
token="$(tuist bazel credential-helper get </dev/null | jq -r '.headers.Authorization[0]')"

if ! capabilities="$(curl -fsS --max-time 30 -H "Authorization: ${token}" \
  "${server_url}/api/remote-execution/${project}/capabilities")"; then
  echo "::notice::Remote execution is unavailable for ${project}; building locally against the remote cache."
  exit 0
fi

endpoint="$(jq -r '.endpoint' <<<"${capabilities}")"
image="$(jq -r '.image' <<<"${capabilities}")"
tuist bazel setup --remote-executor "${endpoint}" --execution-image "${image}"
echo "Remote execution: ${endpoint} with image ${image}, up to $(jq -r '.max_concurrency' <<<"${capabilities}") concurrent actions."
