#!/bin/bash
# shellcheck disable=SC2329
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }

run_install() {
  TUIST_RUNNER_PAYLOAD_DIR="$work/payload" \
    TUIST_RUNNER_PAYLOAD_DEST_ROOT="$work/root" \
    TUIST_RUNNER_PAYLOAD_HALT="touch $work/halted" \
    bash "$ROOT/install-payload.sh" > "$work/output" 2>&1
}

payload_file() {
  mkdir -p "$(dirname "$work/payload/$1")"
  printf '%s\n' "$1" > "$work/payload/$1"
  chmod "$2" "$work/payload/$1"
}

mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }

test_boots_the_image_copies_without_a_payload() {
  run_install || fail 'missing payload failed the boot'
  [ ! -e "$work/halted" ] || fail 'halted without a payload'
  [ ! -e "$work/root" ] || fail 'installed something without a payload'
}

test_installs_payload_over_the_image() {
  payload_file VERSION 0644
  payload_file opt/tuist/dispatch-poll.sh 0755
  payload_file opt/tuist/buildkite-hooks/pre-exit 0755
  payload_file usr/local/bin/tuist-cache-volume 0755
  payload_file opt/tuist/notes.txt 0644
  mkdir -p "$work/root/opt/tuist"
  echo old > "$work/root/opt/tuist/dispatch-poll.sh"

  run_install || fail "install failed: $(cat "$work/output")"

  [ "$(cat "$work/root/opt/tuist/dispatch-poll.sh")" = opt/tuist/dispatch-poll.sh ] || fail 'kept the image copy'
  [ "$(mode_of "$work/root/opt/tuist/buildkite-hooks/pre-exit")" = 755 ] || fail 'hook not executable'
  [ "$(mode_of "$work/root/usr/local/bin/tuist-cache-volume")" = 755 ] || fail 'cache client not executable'
  [ "$(mode_of "$work/root/opt/tuist/notes.txt")" = 644 ] || fail 'made a data file executable'
  [ ! -e "$work/root/VERSION" ] || fail 'installed VERSION'
  grep -q 'installed runner payload VERSION' "$work/output" || fail 'did not log the payload version'
  [ ! -e "$work/halted" ] || fail 'halted after a good install'
}

test_halts_on_a_path_outside_the_payload_roots() {
  payload_file VERSION 0644
  payload_file etc/sudoers.d/runner 0644

  run_install && fail 'installed a file outside the payload roots'
  [ -e "$work/halted" ] || fail 'did not halt'
  [ ! -e "$work/root/etc" ] || fail 'wrote outside the payload roots'
}

test_halts_without_a_version() {
  payload_file opt/tuist/dispatch-poll.sh 0755

  run_install && fail 'accepted a payload without VERSION'
  [ -e "$work/halted" ] || fail 'did not halt'
}

for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
  work=$(mktemp -d)
  ( "$t" ) || { rm -rf "$work"; exit 1; }
  rm -rf "$work"
  echo "ok $t"
done
