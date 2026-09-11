#!/usr/bin/env bash
set -u -o pipefail

attempt_log="$(mktemp)"
trap 'rm -f "${attempt_log}"' EXIT

for attempt in 1 2 3; do
  : >"${attempt_log}"
  "$@" 2>&1 | tee "${attempt_log}"
  command_status=${PIPESTATUS[0]}

  if [ "${command_status}" -eq 0 ]; then
    exit 0
  fi

  if [ "${attempt}" -eq 3 ] || ! grep -Eiq \
    'GET returned (408|429|500|502|503|504)|UnknownHostException|temporary failure in name resolution|connection (reset|timed out)' \
    "${attempt_log}"; then
    exit "${command_status}"
  fi

  delay=$((attempt * 5))
  echo "::warning::Bazel repository download failed on attempt ${attempt}; retrying in ${delay} seconds"
  sleep "${delay}"
done
