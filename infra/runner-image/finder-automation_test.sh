#!/bin/bash
# Disposable SQLite only: extract the grant functions without running dispatch.
# shellcheck disable=SC2329
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SQLITE=/usr/bin/sqlite3
# access matches the schema captured from the macOS 26.6.2 candidate VM.
SCHEMA="CREATE TABLE policies (id INTEGER PRIMARY KEY);
CREATE TABLE access (
 service TEXT NOT NULL, client TEXT NOT NULL, client_type INTEGER NOT NULL,
 auth_value INTEGER NOT NULL, auth_reason INTEGER NOT NULL, auth_version INTEGER NOT NULL,
 csreq BLOB, policy_id INTEGER, indirect_object_identifier_type INTEGER,
 indirect_object_identifier TEXT NOT NULL DEFAULT 'UNUSED', indirect_object_code_identity BLOB,
 flags INTEGER, last_modified INTEGER NOT NULL DEFAULT (CAST(strftime('%s','now') AS INTEGER)),
 pid INTEGER, pid_version INTEGER, boot_uuid TEXT NOT NULL DEFAULT 'UNUSED',
 last_reminded INTEGER NOT NULL DEFAULT (CAST(strftime('%s','now') AS INTEGER)),
 PRIMARY KEY (service, client, client_type, indirect_object_identifier),
 FOREIGN KEY (policy_id) REFERENCES policies(id) ON DELETE CASCADE ON UPDATE CASCADE);"

fail() { echo "FAIL: $*" >&2; exit 1; }
eq() { [ "$1" = "$2" ] || fail "expected [$1], got [$2]"; }
expect_success() { "$@" || fail "command failed: $*"; }
expect_failure() { if "$@"; then fail "command unexpectedly succeeded: $*"; fi; }
sql() { "$SQLITE" -batch -bail "$DB" "$@" || fail 'fixture SQL failed'; }

fixture() {
  eval "$(awk '/^finder_tcc_query\(\)|^approve_finder_automation\(\)/ {copy=1} copy {print} copy && /^}$/ {copy=0}' "$ROOT/dispatch-poll.sh")"
  declare -F finder_tcc_query >/dev/null || fail 'query extraction failed'
  declare -F approve_finder_automation >/dev/null || fail 'grant extraction failed'
  sleep() { :; }
}

test_exact_grants_are_verified_and_idempotent() {
  expect_success approve_finder_automation "$DB"
  expect_success approve_finder_automation "$DB"
  eq $'/Users/runner/actions-runner/bin/Runner.Listener|2|1|com.apple.finder\n/bin/bash|2|1|com.apple.finder' \
    "$(sql 'SELECT client,auth_value,client_type,indirect_object_identifier FROM access ORDER BY client;')"
  eq 2 "$(sql "SELECT count(*) FROM access WHERE hex(indirect_object_code_identity) LIKE 'FADE0C00%';")"
}

test_grants_preserve_guest_schema_defaults() {
  expect_success approve_finder_automation "$DB"
  eq 2 "$(sql "SELECT count(*) FROM access WHERE boot_uuid='UNUSED' AND last_reminded>0 AND pid IS NULL AND pid_version IS NULL AND policy_id IS NULL;")"
}

test_valid_grants_are_not_rewritten() {
  expect_success approve_finder_automation "$DB"
  sql "CREATE TRIGGER reject_rewrite BEFORE INSERT ON access BEGIN SELECT RAISE(ABORT,'must not rewrite'); END;"
  expect_success approve_finder_automation "$DB"
}

test_changed_grants_are_repaired() {
  expect_success approve_finder_automation "$DB"
  sql 'UPDATE access SET auth_value=0;'
  expect_success approve_finder_automation "$DB"
  eq 2 "$(sql 'SELECT count(*) FROM access WHERE auth_value=2;')"
}

test_missing_database_is_not_created() {
  rm "$DB"
  expect_failure approve_finder_automation "$DB"
  expect_failure test -e "$DB"
}

test_schema_readiness_is_retried() {
  rm "$DB"; touch "$DB"
  finder_tcc_query() {
    if [ ! -e "${DB}.ready" ]; then touch "${DB}.ready"; return 1; fi
    if [ ! -e "${DB}.schema" ]; then sql "$SCHEMA"; touch "${DB}.schema"; fi
    "$SQLITE" -batch -bail "$@"
  }
  expect_success approve_finder_automation "$DB"
  eq 2 "$(sql 'SELECT count(*) FROM access;')"
}

test_schema_failure_does_not_report_success() {
  sql 'DROP TABLE access; CREATE TABLE access (service TEXT, client TEXT);'
  expect_failure approve_finder_automation "$DB" >"${DB}.output" 2>&1
  expect_failure grep -q 'Finder grants verified\|Finder grants repaired' "${DB}.output"
}

test_second_client_failure_rolls_back_first() {
  sql "CREATE TRIGGER refuse_bash BEFORE INSERT ON access WHEN NEW.client='/bin/bash' BEGIN SELECT RAISE(ABORT,'denied'); END;"
  expect_failure approve_finder_automation "$DB"
  eq 0 "$(sql 'SELECT count(*) FROM access;')"
}

test_success_without_rows_is_not_approval() {
  finder_tcc_query() { echo 0; }
  expect_failure approve_finder_automation "$DB"
}

test_real_database_lock_is_retried() {
  mkfifo "${DB}.pipe"
  "$SQLITE" -batch -bail "$DB" <"${DB}.pipe" >"${DB}.locker-log" 2>&1 &
  locker=$!
  echo "$locker" >"${DB}.pid"
  exec 3>"${DB}.pipe"
  printf 'BEGIN EXCLUSIVE;\n.shell touch "%s"\n' "${DB}.locked" >&3
  for ((attempt=0; attempt<100; attempt++)); do
    [ ! -e "${DB}.locked" ] || break
    /bin/sleep 0.01
  done
  expect_success test -e "${DB}.locked"
  finder_tcc_query() {
    local rc
    "$SQLITE" -batch -bail -cmd '.timeout 1000' "$@"
    rc=$?
    if [ ! -e "${DB}.released" ]; then
      [ "$rc" -ne 0 ] || fail 'fixture failed to hold a real lock'
      echo locked >>"${DB}.calls"
      printf 'COMMIT;\n' >&3
      touch "${DB}.released"
    fi
    return "$rc"
  }
  expect_success approve_finder_automation "$DB"
  exec 3>&-
  expect_success wait "$locker"
  rm "${DB}.pid"
  eq locked "$(<"${DB}.calls")"
  eq 2 "$(sql 'SELECT count(*) FROM access;')"
}

if [ "${1:-}" = --case ]; then
  DB="$3/TCC.db"
  trap '[ ! -f "${DB}.pid" ] || kill "$(<"${DB}.pid")" 2>/dev/null || true' EXIT
  sql "$SCHEMA"
  fixture
  "$2"
  exit "$?"
fi

[ -x "$SQLITE" ] || fail 'sqlite3 is required'
fixtures=$(mktemp -d)
trap 'rm -rf "$fixtures"' EXIT
passed=0; failed=0
for name in $(declare -F | awk '$3 ~ /^test_/ {print $3}'); do
  directory="$fixtures/$name"
  mkdir "$directory"
  /bin/bash "$ROOT/finder-automation_test.sh" --case "$name" "$directory" >"$directory/output" 2>&1 &
  pid=$!
  (
    sleeper=''
    trap '[ -z "$sleeper" ] || kill "$sleeper" 2>/dev/null; exit 0' TERM
    /bin/sleep 12 & sleeper=$!; wait "$sleeper"
    kill -TERM "$pid" 2>/dev/null
    /bin/sleep 1 & sleeper=$!; wait "$sleeper"
    kill -KILL "$pid" 2>/dev/null
  ) >/dev/null 2>&1 &
  timer=$!
  wait "$pid" 2>/dev/null; rc=$?
  kill "$timer" 2>/dev/null || true
  wait "$timer" 2>/dev/null || true
  if [ "$rc" -eq 0 ]; then
    echo "PASS: $name"; passed=$((passed + 1))
  else
    echo "FAIL: $name"; cat "$directory/output"; failed=$((failed + 1))
  fi
done
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
