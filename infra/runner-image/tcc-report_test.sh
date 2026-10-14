#!/bin/bash
# Extract functions only. Never stream host logs or invoke Finder.
# shellcheck disable=SC2329
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }
eq() { [ "$1" = "$2" ] || fail "expected [$1], got [$2]"; }
event() { jq -nc --arg msg "$1" --argjson pid "${2:-410}" --argjson thread "${3:-10}" '{timestamp:"2026-10-14 14:00:00",processID:$pid,threadID:$thread,eventMessage:$msg}'; }
fixture() {
  eval "$(awk '/^(stream_tcc_log|filter_tcc_log|report_finder_automation|approve_simulator_microphone)\(\)/ {copy=1} copy {print} copy && /^}$/ {copy=0}' "$ROOT/dispatch-poll.sh")"
  # shellcheck disable=SC2034
  TCC_LOG="$work/tcc.log"; TCC_LOG_PID=''; RUNNER_TCC_DB="$work/TCC.db"
  : > "$TCC_LOG"
}
filter() {
  declare -F filter_tcc_log >/dev/null || fail 'filter function missing'
  filter_tcc_log > "$work/report"
}
test_stream_captures_complete_events() {
  grep -q '/usr/bin/log stream --level info --style ndjson' "$ROOT/dispatch-poll.sh" || fail 'stream omits service context or event boundaries'
}
test_multiline_service_and_no_id_attribution() {
  {
    event $'REQUEST_MSG: msgID=900.1, msg={\n service="kTCCServiceAppleEvents"\n target_identifier="/bin/bash"\n}'
    event 'AttributionChain: responsible={identifier=com.apple.bash, responsible_path=/bin/bash}, requesting={identifier=com.apple.osascript}'
    event 'Handling access request: kTCCServiceAppleEvents:com.apple.finder, authValue: 0, authReason: 4'
  } > "$TCC_LOG"
  filter
  grep -q 'responsible_path=/bin/bash' "$work/report" || fail 'lost attribution without msgID'
  grep -q 'authValue: 0' "$work/report" || fail 'lost decision'
}
test_responsible_attribution_is_not_overwritten() {
  {
    event $'REQUEST_MSG: msgID=900.1, msg={\n service="kTCCServiceAppleEvents"\n}'
    event 'AttributionChain: responsible={responsible_path=/bin/bash}, requesting=appleeventsd'
    event 'AttributionChain: accessing=com.apple.finder, requesting=com.apple.finder'
    event '-[TCCDPlatform promptingPolicyForIdentity:withAttributionChain:]: promptPolicy=2'
    event 'Handling access request: kTCCServiceAppleEvents:com.apple.finder, authValue: 2'
  } > "$TCC_LOG"
  filter
  grep -q 'responsible_path=/bin/bash' "$work/report" || fail 'later metadata displaced charged process'
}

test_unrelated_services_are_excluded() {
  {
    event $'REQUEST_MSG: msgID=500.1, msg={\n service="kTCCServiceSystemPolicyDownloadsFolder"\n}'
    event 'AUTHREQ_ATTRIBUTION: msgID=500.1, responsible=com.apple.finder, accessing=osascript'
    event 'AUTHREQ_RESULT: msgID=500.1, authValue=0'
    event 'AUTHREQ_SUBJECT: msgID=900.1, subject=com.apple.finder'
    event 'AUTHREQ_RESULT: msgID=900.1, authValue=0'
  } > "$TCC_LOG"
  filter
  ! grep -q '500.1' "$work/report" || fail 'leaked unrelated service'
  grep -q '900.1' "$work/report" || fail 'lost Finder request'
}
test_no_id_non_apple_decision_is_not_inherited() {
  {
    event $'REQUEST_MSG: msgID=900.1, msg={\n service="kTCCServiceAppleEvents"\n}'
    event 'Handling access request: kTCCServiceAppleEvents:com.apple.finder, authValue: 2'
    event 'Handling access request to kTCCServiceListenEvent, from Sub:{com.apple.finder}, authValue: 0'
  } > "$TCC_LOG"
  filter
  ! grep -q kTCCServiceListenEvent "$work/report" || fail 'inherited another service decision'
  grep -q 'authValue: 2' "$work/report" || fail 'overwrote AppleEvents result'
}

test_daemon_ids_do_not_collide() {
  {
    event 'AUTHREQ_SUBJECT: msgID=1.1, subject=com.apple.finder' 410
    event 'AUTHREQ_RESULT: msgID=1.1, authValue=0' 410
    event 'AUTHREQ_ATTRIBUTION: msgID=1.1, unrelated-private-path' 195
  } > "$TCC_LOG"
  filter
  ! grep -q unrelated-private-path "$work/report" || fail 'merged different daemons'
}
test_denial_survives_later_successes() {
  {
    event 'AUTHREQ_SUBJECT: msgID=1.1, subject=com.apple.finder'
    event 'AUTHREQ_ATTRIBUTION: msgID=1.1, responsible_path=/denied-launcher'
    event 'AUTHREQ_RESULT: msgID=1.1, authValue=0, authReason=4'
    jq -nc 'range(2;100) as $i |
      {timestamp:"now",processID:410,threadID:10,eventMessage:("AUTHREQ_SUBJECT: msgID=\($i).1, subject=com.apple.finder")},
      {timestamp:"now",processID:410,threadID:10,eventMessage:("AUTHREQ_RESULT: msgID=\($i).1, authValue=2")}'
  } > "$TCC_LOG"
  filter
  grep -q /denied-launcher "$work/report" || fail 'later successes displaced denial'
  [ "$(wc -l < "$work/report")" -le 30 ] || fail 'unbounded report'
}
test_explicit_denial_beats_later_unknown_state() {
  {
    event 'AUTHREQ_SUBJECT: msgID=1.1, subject=com.apple.finder'
    event 'AUTHREQ_RESULT: msgID=1.1, authValue=0, authReason=4'
    event 'AUTHREQ_RESULT: msgID=1.1, authValue=2'
    jq -nc 'range(2;40) as $i |
      {timestamp:"now",processID:410,threadID:10,eventMessage:("AUTHREQ_SUBJECT: msgID=\($i).1, subject=com.apple.finder")},
      {timestamp:"now",processID:410,threadID:10,eventMessage:("AUTHREQ_RESULT: msgID=\($i).1, authValue=1")}'
  } > "$TCC_LOG"
  filter
  grep -q 'msgID=1.1, authValue=0' "$work/report" || fail 'unknown/allowed states displaced explicit denial'
}

test_long_attribution_is_retained() {
  padding=$(printf '%01000d' 0)
  {
    event 'AUTHREQ_SUBJECT: msgID=1.1, subject=com.apple.finder'
    event "AUTHREQ_ATTRIBUTION: msgID=1.1, responsible=/bin/bash, $padding requesting=/Runner.Listener"
  } > "$TCC_LOG"
  filter
  grep -q requesting=/Runner.Listener "$work/report" || fail 'truncated requesting identity'
}
test_incomplete_json_is_ignored() {
  {
    echo 'Filtering log data'
    event 'AUTHREQ_SUBJECT: msgID=1.1, subject=com.apple.finder'
    printf '{"eventMessage":"partial'
  } > "$TCC_LOG"
  filter
  grep -q com.apple.finder "$work/report" || fail 'partial record broke report'
}
test_report_fits_host_tail_and_excludes_other_targets() {
  stat() { echo db-metadata; }
  ps() { for ((i=0;i<8;i++)); do printf '123 runner now /usr/libexec/tccd\n'; done; }
  /usr/bin/sqlite3 "$RUNNER_TCC_DB" "CREATE TABLE access (client TEXT,auth_value INTEGER,auth_reason INTEGER,last_modified INTEGER,service TEXT,indirect_object_identifier TEXT); INSERT INTO access VALUES ('unrelated-private-client',2,3,0,'kTCCServiceAppleEvents','com.apple.other');"
  padding=$(printf '%02000d' 0)
  /usr/bin/sqlite3 "$RUNNER_TCC_DB" "WITH RECURSIVE rows(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM rows WHERE n<10) INSERT INTO access SELECT '$padding',2,3,0,'kTCCServiceAppleEvents','com.apple.finder' FROM rows;"
  jq -nc --arg padding "$padding" 'range(0;10) as $i |
    {timestamp:"now",processID:410,threadID:10,eventMessage:("AUTHREQ_SUBJECT: msgID=\($i).1, subject=com.apple.finder " + $padding)},
    {timestamp:"now",processID:410,threadID:10,eventMessage:("AUTHREQ_ATTRIBUTION: msgID=\($i).1, responsible=" + $padding)},
    {timestamp:"now",processID:410,threadID:10,eventMessage:("AUTHREQ_RESULT: msgID=\($i).1, authValue=0, " + $padding)}' >> "$TCC_LOG"
  report_finder_automation > "$work/report" 2>&1
  [ "$(wc -c < "$work/report")" -lt 65536 ] || fail 'report exceeds host byte tail'
  [ "$(wc -l < "$work/report")" -lt 200 ] || fail 'report exceeds host line tail'
  ! grep -q unrelated-private-client "$work/report" || fail 'leaked another target grant'
  grep -q authValue=0 "$work/report" || fail 'lost denial'
}

test_empty_capture_is_safe() { filter; [ ! -s "$work/report" ] || fail 'invented events'; }
test_teardown_cannot_wait_forever() {
  stat() { echo metadata; }
  ps() { :; }
  filter_tcc_log() { /bin/sleep 30; }
  SECONDS=0
  report_finder_automation > "$work/report" 2>&1
  [ "$SECONDS" -lt 9 ] || fail 'report blocked teardown'
}
test_stream_stop_is_bounded_and_idempotent() {
  stat() { :; }; ps() { :; }; filter_tcc_log() { :; }
  /bin/sh -c 'trap "" TERM; exec sleep 30' &
  TCC_LOG_PID=$!
  /bin/sleep 0.1
  old_pid=$TCC_LOG_PID
  SECONDS=0
  report_finder_automation > "$work/report" 2>&1
  [ "$SECONDS" -lt 4 ] || fail 'stream stop blocked'
  [ -z "$TCC_LOG_PID" ] || fail 'stale stream PID'
  ! kill -0 "$old_pid" 2>/dev/null || fail 'stream survived'
  report_finder_automation >/dev/null 2>&1
}
test_simulator_microphone_approval_is_idempotent() {
  /usr/bin/sqlite3 "$RUNNER_TCC_DB" "CREATE TABLE access (service TEXT NOT NULL, client TEXT NOT NULL, client_type INTEGER NOT NULL, auth_value INTEGER NOT NULL, auth_reason INTEGER NOT NULL, auth_version INTEGER NOT NULL, csreq BLOB, policy_id INTEGER, indirect_object_identifier_type INTEGER, indirect_object_identifier TEXT NOT NULL DEFAULT 'UNUSED', indirect_object_code_identity BLOB, flags INTEGER, last_modified INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (service, client, client_type, indirect_object_identifier));"
  approve_simulator_microphone > "$work/output" || fail 'approval failed'
  approve_simulator_microphone >> "$work/output" || fail 'second approval failed'
  eq 'kTCCServiceMicrophone|com.apple.CoreSimulator.SimulatorTrampoline|0|2|UNUSED' \
    "$(/usr/bin/sqlite3 "$RUNNER_TCC_DB" "SELECT service, client, client_type, auth_value, indirect_object_identifier FROM access;")"
  eq 2 "$(grep -c 'Simulator microphone approved' "$work/output")"
}
test_simulator_microphone_approval_skips_missing_database() {
  approve_simulator_microphone > "$work/output" || fail 'missing database failed the boot'
  [ ! -e "$RUNNER_TCC_DB" ] || fail 'created a database tccd does not own'
}
if [ "${1:-}" = --case ]; then
  work="$3"
  fixture
  trap '[ -z "$TCC_LOG_PID" ] || kill -KILL "$TCC_LOG_PID" 2>/dev/null || true' EXIT
  "$2"
  exit "$?"
fi
fixtures=$(mktemp -d)
trap 'rm -rf "$fixtures"' EXIT
passed=0; failed=0
for name in $(declare -F | awk '$3 ~ /^test_/ {print $3}'); do
  directory="$fixtures/$name"; mkdir "$directory"
  set -m
  /bin/bash "$ROOT/tcc-report_test.sh" --case "$name" "$directory" > "$directory/output" 2>&1 &
  pid=$!
  set +m
  (
    sleeper=''
    trap '[ -z "$sleeper" ] || kill "$sleeper" 2>/dev/null; exit 0' TERM
    /bin/sleep 10 & sleeper=$!; wait "$sleeper"
    kill -TERM -- "-$pid" 2>/dev/null
    /bin/sleep 1 & sleeper=$!; wait "$sleeper"
    kill -KILL -- "-$pid" 2>/dev/null
  ) >/dev/null 2>&1 &
  timer=$!
  wait "$pid" 2>/dev/null; rc=$?
  kill "$timer" 2>/dev/null || true
  wait "$timer" 2>/dev/null || true
  if [ "$rc" -eq 0 ]; then echo "PASS: $name"; passed=$((passed+1));
  else echo "FAIL: $name"; cat "$directory/output"; failed=$((failed+1)); fi
done
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
