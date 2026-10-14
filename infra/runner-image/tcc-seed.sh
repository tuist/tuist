#!/bin/bash
# Build-time TCC seeding for the runner account (experiment).
#
#   tcc-seed.sh wait      wait for runner's session, its tccd and its TCC.db
#   tcc-seed.sh seed      write the standing approvals and read them back
#   tcc-seed.sh snapshot <label>
#                         record the database's identity and rows under
#                         /var/db/tuist-tcc-evidence/<label>.txt
#
# Runs as root (Packer provisions through sudo).

set -euo pipefail

DB="/Users/runner/Library/Application Support/com.apple.TCC/TCC.db"
EVIDENCE=/var/db/tuist-tcc-evidence
FINDER_REQUIREMENT="X'fade0c000000002c00000001000000060000000200000010636f6d2e6170706c652e66696e64657200000003'"

rows() {
  /usr/bin/sqlite3 -readonly -cmd '.timeout 5000' "${DB}" \
    "SELECT service, client, client_type, auth_value, auth_reason, length(indirect_object_code_identity), last_modified FROM access WHERE service IN ('kTCCServiceAppleEvents', 'kTCCServiceMicrophone') ORDER BY 1, 2;"
}

snapshot() {
  local label=$1 out
  mkdir -p "${EVIDENCE}"
  out="${EVIDENCE}/${label}.txt"
  {
    echo "label=${label} at=$(date -u +%FT%TZ) boot=$(sysctl -n kern.boottime | sed 's/.*} //')"
    echo "console=$(stat -f %Su /dev/console) hw_uuid=$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformUUID/ { print $4 }')"
    stat -f 'db inode=%i birth=%SB mtime=%Sm owner=%Su flags=%Sf size=%z' -t '%FT%T' "${DB}" 2>&1 || true
    stat -f 'dir inode=%i birth=%SB owner=%Su flags=%Sf' -t '%FT%T' "$(dirname "${DB}")" 2>&1 || true
    ls -laO@e "$(dirname "${DB}")" 2>&1 || true
    shasum -a 256 "${DB}" 2>&1 || true
    /usr/bin/sqlite3 -readonly -cmd '.timeout 5000' "${DB}" "SELECT key, value FROM admin;" 2>&1 || true
    rows 2>&1 || true
    ps -axo pid=,user=,lstart=,comm= | awk '$NF ~ /(^|\/)tccd$/'
  } | tee "${out}"
}

wait_for_session() {
  local waited=0
  while [ "${waited}" -lt 300 ]; do
    if [ "$(stat -f %Su /dev/console)" = runner ] &&
      ps -axo user=,comm= | awk '$1 == "runner" && $2 ~ /(^|\/)tccd$/ { found = 1 } END { exit !found }' &&
      [ -f "${DB}" ]; then
      echo "tcc-seed: runner session, tccd and TCC.db present after ${waited}s"
      return 0
    fi
    sleep 2
    waited=$((waited + 2))
  done
  echo "tcc-seed: runner session or its TCC.db never appeared" >&2
  ps -axo pid=,user=,comm= | grep -E 'loginwindow|tccd' >&2 || true
  ls -la "$(dirname "${DB}")" >&2 || true
  return 1
}

seed() {
  local client
  for client in /Users/runner/actions-runner/bin/Runner.Listener /bin/bash; do
    sudo -u runner /usr/bin/sqlite3 -cmd '.timeout 10000' "${DB}" \
      "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, csreq, indirect_object_identifier_type, indirect_object_identifier, indirect_object_code_identity, flags, last_modified) VALUES ('kTCCServiceAppleEvents', '${client}', 1, 2, 3, 1, NULL, 0, 'com.apple.finder', ${FINDER_REQUIREMENT}, 0, CAST(strftime('%s','now') AS INTEGER));"
  done
  sudo -u runner /usr/bin/sqlite3 -cmd '.timeout 10000' "${DB}" \
    "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, csreq, indirect_object_identifier_type, indirect_object_identifier, indirect_object_code_identity, flags, last_modified) VALUES ('kTCCServiceMicrophone', 'com.apple.CoreSimulator.SimulatorTrampoline', 0, 2, 3, 1, NULL, NULL, 'UNUSED', NULL, 0, CAST(strftime('%s','now') AS INTEGER));"
  verify
}

verify() {
  local count
  count=$(/usr/bin/sqlite3 -readonly -cmd '.timeout 5000' "${DB}" \
    "SELECT count(*) FROM access WHERE auth_value = 2 AND ((service = 'kTCCServiceAppleEvents' AND indirect_object_identifier = 'com.apple.finder' AND indirect_object_code_identity IS NOT NULL AND client IN ('/Users/runner/actions-runner/bin/Runner.Listener', '/bin/bash')) OR (service = 'kTCCServiceMicrophone' AND client = 'com.apple.CoreSimulator.SimulatorTrampoline' AND client_type = 0));")
  [ "${count}" = 3 ] || {
    echo "tcc-seed: expected 3 approvals in ${DB}, found ${count}" >&2
    return 1
  }
  echo "tcc-seed: 3 approvals present"
}

case "${1:-}" in
  wait) wait_for_session ;;
  seed) seed ;;
  verify) verify ;;
  snapshot) snapshot "${2:?label}" ;;
  *)
    echo "usage: $0 wait|seed|verify|snapshot <label>" >&2
    exit 64
    ;;
esac
