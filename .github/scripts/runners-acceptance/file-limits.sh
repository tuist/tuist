#!/usr/bin/env bash
# Proves job steps on a Linux runner get at least the open-file limit a
# GitHub-hosted runner gives them (65536), so file-heavy jobs such as databases,
# search engines and large node_modules builds do not hit EMFILE. The Kata guest
# kernel defaults to 1024, so a runtime or guest change can lower it quietly.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

minimum=65536
soft="$(ulimit -Sn)"
hard="$(ulimit -Hn)"

for limit in "${soft}" "${hard}"; do
  if [ "${limit}" != unlimited ] && [ "${limit}" -lt "${minimum}" ]; then
    fail "Runner file limits" "job steps get RLIMIT_NOFILE soft=${soft} hard=${hard}, below the ${minimum} GitHub-hosted runners give"
  fi
done

pass "Runner file limits: RLIMIT_NOFILE soft=${soft} hard=${hard}"
