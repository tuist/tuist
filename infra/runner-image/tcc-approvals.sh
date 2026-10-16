#!/bin/bash
# Standing TCC approvals for the `runner` account.
#
#   tcc-approvals.sh wait    wait for runner's login session to create its TCC.db
#   tcc-approvals.sh seed    write the approvals into it and read them back
#   tcc-approvals.sh check   list missing approvals; exit 1 when any are
#
# The image build runs `wait` and `seed` while `runner` is logged in, and
# `check` after a further reboot. dispatch-poll.sh runs `check` at boot.
# See infra/runner-image/AGENTS.md for why each row has the shape it has.

set -uo pipefail

DB="${TUIST_TCC_DB:-/Users/runner/Library/Application Support/com.apple.TCC/TCC.db}"
FINDER_REQUIREMENT="X'fade0c000000002c00000001000000060000000200000010636f6d2e6170706c652e66696e64657200000003'"
FINDER_CLIENTS="/Users/runner/actions-runner/bin/Runner.Listener /bin/bash"
SIMULATOR_CLIENT=com.apple.CoreSimulator.SimulatorTrampoline

wait_for_database() {
  local waited=0
  while [ "${waited}" -lt 300 ]; do
    if [ "$(stat -f %Su /dev/console)" = runner ] && [ -f "${DB}" ]; then
      return 0
    fi
    sleep 2
    waited=$((waited + 2))
  done
  echo "tcc-approvals: ${DB} did not appear within ${waited}s of runner's login; macOS may have moved the user TCC database" >&2
  return 1
}

seed() {
  local client
  for client in ${FINDER_CLIENTS}; do
    /usr/bin/sqlite3 -cmd '.timeout 10000' "${DB}" \
      "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, csreq, indirect_object_identifier_type, indirect_object_identifier, indirect_object_code_identity, flags, last_modified) VALUES ('kTCCServiceAppleEvents', '${client}', 1, 2, 3, 1, NULL, 0, 'com.apple.finder', ${FINDER_REQUIREMENT}, 0, CAST(strftime('%s','now') AS INTEGER));" || return 1
  done
  /usr/bin/sqlite3 -cmd '.timeout 10000' "${DB}" \
    "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, csreq, indirect_object_identifier_type, indirect_object_identifier, indirect_object_code_identity, flags, last_modified) VALUES ('kTCCServiceMicrophone', '${SIMULATOR_CLIENT}', 0, 2, 3, 1, NULL, NULL, 'UNUSED', NULL, 0, CAST(strftime('%s','now') AS INTEGER));" || return 1
  check
}

granted() {
  [ "$(/usr/bin/sqlite3 -readonly -cmd '.timeout 5000' "${DB}" "$1" 2>/dev/null)" = 1 ]
}

check() {
  local client missing=""
  [ -f "${DB}" ] || {
    echo "tcc-approvals: ${DB} missing"
    return 1
  }
  for client in ${FINDER_CLIENTS}; do
    granted "SELECT count(*) FROM access WHERE service = 'kTCCServiceAppleEvents' AND client = '${client}' AND client_type = 1 AND auth_value = 2 AND indirect_object_identifier = 'com.apple.finder' AND indirect_object_code_identity IS NOT NULL;" ||
      missing="${missing} finder:${client}"
  done
  granted "SELECT count(*) FROM access WHERE service = 'kTCCServiceMicrophone' AND client = '${SIMULATOR_CLIENT}' AND client_type = 0 AND auth_value = 2;" ||
    missing="${missing} microphone:${SIMULATOR_CLIENT}"
  if [ -n "${missing}" ]; then
    echo "tcc-approvals: missing${missing}"
    return 1
  fi
  echo "tcc-approvals: all approvals present"
}

case "${1:-}" in
  wait) wait_for_database ;;
  seed) seed ;;
  check) check ;;
  *)
    echo "usage: $0 wait|seed|check" >&2
    exit 64
    ;;
esac
