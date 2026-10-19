#!/bin/bash
# Standing TCC approvals for the `runner` account.
#
#   tcc-approvals.sh wait    wait for runner's login session to create its TCC.db
#   tcc-approvals.sh seed    write the approvals into it and read them back
#   tcc-approvals.sh check   list missing approvals; exit 1 when any are
#   tcc-approvals.sh path    print where runner's TCC.db is
#
# Every command runs as `runner`. The image build runs `wait` and `seed`
# while `runner` is logged in, and `check` after a further reboot.
# dispatch-poll.sh runs `check` and `path` at boot. See
# infra/runner-image/AGENTS.md for why each row has the shape it has.

set -uo pipefail

HOME_DB="/Users/runner/Library/Application Support/com.apple.TCC/TCC.db"
CONTAINERS="${TUIST_TCC_CONTAINERS:-/private/var/containers/Data/ProtectedSystem}"
FINDER_REQUIREMENT="X'fade0c000000002c00000001000000060000000200000010636f6d2e6170706c652e66696e64657200000003'"
FINDER_CLIENTS="/Users/runner/actions-runner/bin/Runner.Listener /bin/bash"
SIMULATOR_CLIENT=com.apple.CoreSimulator.SimulatorTrampoline

# macOS 26 keeps the user database in runner's home. macOS 27 keeps it in a
# data container named by a UUID, one per user and daemon, and only tccd's
# holds this path. `-O` keeps it to runner's own container.
database() {
  if [ -n "${TUIST_TCC_DB:-}" ]; then
    echo "${TUIST_TCC_DB}"
    return 0
  fi
  if [ -f "${HOME_DB}" ]; then
    echo "${HOME_DB}"
    return 0
  fi
  local db
  for db in "${CONTAINERS}"/*/Data/Library/"Application Support"/com.apple.TCC/TCC.db; do
    if [ -f "${db}" ] && [ -O "${db}" ]; then
      echo "${db}"
      return 0
    fi
  done
  return 1
}

DB="$(database)" || DB=""

wait_for_database() {
  local waited=0
  while [ "${waited}" -lt 300 ]; do
    DB="$(database)" || DB=""
    if [ "$(stat -f %Su /dev/console)" = runner ] && [ -n "${DB}" ] && [ -f "${DB}" ]; then
      echo "tcc-approvals: ${DB}"
      return 0
    fi
    sleep 2
    waited=$((waited + 2))
  done
  echo "tcc-approvals: runner's TCC.db did not appear within ${waited}s of runner's login, neither at ${HOME_DB} nor in a container under ${CONTAINERS}; macOS may have moved the user TCC database" >&2
  return 1
}

seed() {
  local client
  [ -n "${DB}" ] || {
    echo "tcc-approvals: runner's TCC.db missing" >&2
    return 1
  }
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
  if [ -z "${DB}" ]; then
    echo "tcc-approvals: runner's TCC.db missing"
    return 1
  fi
  if [ ! -f "${DB}" ]; then
    echo "tcc-approvals: ${DB} missing"
    return 1
  fi
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
  path) [ -n "${DB}" ] && echo "${DB}" ;;
  *)
    echo "usage: $0 wait|seed|check|path" >&2
    exit 64
    ;;
esac
