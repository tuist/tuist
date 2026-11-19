#!/bin/bash
# Extracts the clock functions from dispatch-poll.sh and runs them against
# synthetic response headers. `date` and `sudo` are stand-ins, so the test
# never touches the clock and runs on macOS and Linux alike.
# shellcheck disable=SC2034
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }
eq() { [ "$1" = "$2" ] || fail "expected [$1], got [$2]"; }

eval "$(awk '/^(server_clock_offset|step_clock_to_server)\(\)/ {copy=1} copy {print} copy && /^}$/ {copy=0}' "$ROOT/dispatch-poll.sh")"
for function in server_clock_offset step_clock_to_server; do
  declare -F "$function" >/dev/null || fail "$function missing"
done
CLOCK_STEP_THRESHOLD_SECONDS=2
base=$(mktemp -d)
trap 'rm -rf "$base"' EXIT

if command date --version >/dev/null 2>&1; then
  gnu_date=1
else
  gnu_date=0
fi

# A stand-in for macOS date: answers the BSD forms dispatch-poll.sh uses, with
# the guest's "now" frozen at NOW.
date() {
  if [ "$*" = "-u +%s" ]; then
    echo "${NOW}"
  elif [ "$#" = 6 ] && [ "$1 $2 $3" = "-j -u -f" ] && [ "$6" = "+%s" ]; then
    if [ "${gnu_date}" = "1" ]; then
      command date -u -d "$5" +%s
    else
      LC_ALL=C command date -j -u -f "$4" "$5" +%s
    fi
  elif [ "$#" = 4 ] && [ "$1 $2" = "-u -r" ]; then
    if [ "${gnu_date}" = "1" ]; then
      command date -u -d "@$3" "$4"
    else
      command date -u -r "$3" "$4"
    fi
  else
    command date "$@"
  fi
}

# A stand-in for sudo: records the command instead of running it.
sudo() {
  echo "$*" >>"${work}/sudo"
  return "${SUDO_STATUS:-0}"
}

# format_epoch EPOCH FORMAT prints EPOCH in UTC with the real date.
format_epoch() {
  if [ "${gnu_date}" = "1" ]; then
    LC_ALL=C command date -u -d "@$1" "$2"
  else
    LC_ALL=C command date -u -r "$1" "$2"
  fi
}

http_date() { format_epoch "$1" '+%a, %d %b %Y %H:%M:%S GMT'; }

setup() {
  work=$(mktemp -d "$base/test.XXXXXX")
  NOW=1793206771
  SUDO_STATUS=0
}

# headers SERVER_EPOCH [DATE_HEADER_NAME] writes an HTTP response whose Date is
# SERVER_EPOCH, with CRLF line endings as curl's --dump-header writes them.
headers() {
  printf 'HTTP/2 204\r\nserver: Cowboy\r\n%s: %s\r\n\r\n' "${2:-date}" "$(http_date "$1")" >"${work}/headers"
}

test_a_clock_minutes_behind_is_stepped_to_the_server() {
  setup
  headers $((NOW + 224))
  eq 224 "$(server_clock_offset "${work}/headers")"
  out=$(step_clock_to_server "${work}/headers")
  eq "/bin/date -u $(format_epoch $((NOW + 224)) +%m%d%H%M%Y.%S)" "$(cat "${work}/sudo")"
  [[ "${out}" == *"clock stepped 224s to the dispatch server's time"* ]] || fail "unexpected log: ${out}"
}

test_a_clock_ahead_of_the_server_is_stepped_back() {
  setup
  headers $((NOW - 90)) Date
  eq -90 "$(server_clock_offset "${work}/headers")"
  step_clock_to_server "${work}/headers" >/dev/null
  [ -s "${work}/sudo" ] || fail 'a clock 90s ahead was not stepped'
}

test_a_clock_within_the_threshold_is_left_alone() {
  setup
  headers $((NOW + 1))
  out=$(step_clock_to_server "${work}/headers")
  [ ! -e "${work}/sudo" ] || fail 'a 1s offset was stepped'
  eq "" "${out}"
}

test_a_response_without_a_date_is_ignored() {
  setup
  printf 'HTTP/2 204\r\nserver: Cowboy\r\n\r\n' >"${work}/headers"
  eq "" "$(server_clock_offset "${work}/headers")"
  step_clock_to_server "${work}/headers" >/dev/null
  step_clock_to_server "${work}/missing" >/dev/null
  [ ! -e "${work}/sudo" ] || fail 'stepped without a server time'
}

test_a_failed_step_is_reported_and_not_fatal() {
  setup
  headers $((NOW + 300))
  SUDO_STATUS=1
  out=$(step_clock_to_server "${work}/headers") || fail 'a failed step returned non-zero'
  [[ "${out}" == *"WARNING could not step the clock 300s"* ]] || fail "unexpected log: ${out}"
}

for test in $(declare -F | awk '{print $3}' | grep '^test_'); do
  "$test"
  echo "ok: $test"
done
