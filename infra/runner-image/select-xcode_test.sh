#!/bin/bash
# Sources select-xcode.sh and runs it against Xcode bundles laid out in a
# temporary directory. `sudo`, `xcode-select`, `xcodebuild` and `xcrun` are
# stand-ins that record their calls, so the test runs on macOS and Linux alike.
# shellcheck disable=SC2034,SC2329
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }
eq() { [ "$1" = "$2" ] || fail "expected [$1], got [$2]"; }

# shellcheck source=select-xcode.sh
source "$ROOT/select-xcode.sh"
base=$(mktemp -d)
trap 'rm -rf "$base"' EXIT

sudo() {
  [ "$1" = -n ] || fail "sudo without -n: $*"
  shift
  echo "sudo $*" >>"${work}/calls"
  "$@"
}

xcode-select() {
  case "$1" in
    -s) printf '%s' "$2" >"${work}/selected" ;;
    -p) printf '%s/Contents/Developer\n' "$(cat "${work}/selected")" ;;
  esac
}

xcodebuild() {
  echo "xcodebuild $* ${DEVELOPER_DIR}" >>"${work}/calls"
  if [ -n "${STOP_AFTER_FIRST:-}" ]; then : >"${XCODE_WARM_STOP_FILE}"; fi
}
xcrun() { echo "xcrun $* ${DEVELOPER_DIR}" >>"${work}/calls"; }

setup() {
  work=$(mktemp -d "$base/test.XXXXXX")
  XCODE_APPS_DIR="${work}/Applications"
  XCODE_WARM_STOP_FILE="${work}/claimed"
  STOP_AFTER_FIRST=
  mkdir -p "${XCODE_APPS_DIR}"
  : >"${work}/calls"
  printf '%s' /Applications/Xcode_default.app >"${work}/selected"
}

# install_xcode lays down a bundle, plus its major-minor alias for a patch or a
# beta, as the base image does.
install_xcode() {
  mkdir -p "${XCODE_APPS_DIR}/Xcode_$1.app/Contents/Developer"
  if [ -n "${2:-}" ]; then ln -s "${XCODE_APPS_DIR}/Xcode_$1.app" "${XCODE_APPS_DIR}/Xcode_$2.app"; fi
}

calls() { cat "${work}/calls"; }

test_a_stable_xcode_is_selected_and_linked() {
  setup
  install_xcode 26.4.1 26.4
  install_xcode 27.2
  out=$(select_xcode 26.4.1) || fail "select failed: ${out}"
  eq "${XCODE_APPS_DIR}/Xcode_26.4.1.app" "$(cat "${work}/selected")"
  eq "${XCODE_APPS_DIR}/Xcode_26.4.1.app" "$(readlink "${XCODE_APPS_DIR}/Xcode.app")"
  [[ "$(calls)" != *xcodebuild* ]] || fail "the claim path launched xcodebuild"
}

test_a_beta_channel_selects_the_newest_beta() {
  setup
  install_xcode 27.3-beta-2
  install_xcode 27.3-beta-10 27.3
  select_xcode 27.3-beta >/dev/null || fail "select failed"
  eq "${XCODE_APPS_DIR}/Xcode_27.3-beta-10.app" "$(cat "${work}/selected")"
}

test_an_xcode_the_image_lacks_changes_nothing() {
  setup
  install_xcode 27.2
  out=$(select_xcode 27.1)
  eq 1 "$?"
  [[ "${out}" == *"WARNING no Xcode 27.1"* ]] || fail "unexpected output: ${out}"
  eq /Applications/Xcode_default.app "$(cat "${work}/selected")"
  [ ! -e "${XCODE_APPS_DIR}/Xcode.app" ] || fail "linked Xcode.app"
  eq "" "$(calls)"
}

test_a_version_cannot_leave_the_applications_directory() {
  setup
  mkdir -p "${work}/Xcode_evil.app"
  select_xcode "../../Xcode_evil" >/dev/null && fail "selected a path outside ${XCODE_APPS_DIR}"
  eq /Applications/Xcode_default.app "$(cat "${work}/selected")"
}

test_a_real_xcode_app_bundle_is_left_alone() {
  setup
  install_xcode 27.2
  mkdir -p "${XCODE_APPS_DIR}/Xcode.app/Contents"
  select_xcode 27.2 >/dev/null || fail "select failed"
  [ ! -L "${XCODE_APPS_DIR}/Xcode.app" ] || fail "replaced the image's Xcode.app"
  [ -d "${XCODE_APPS_DIR}/Xcode.app/Contents" ] || fail "removed the image's Xcode.app"
}

test_an_existing_xcode_app_link_moves() {
  setup
  install_xcode 27.1
  install_xcode 27.2
  select_xcode 27.1 >/dev/null || fail "select failed"
  select_xcode 27.2 >/dev/null || fail "select failed"
  eq "${XCODE_APPS_DIR}/Xcode_27.2.app" "$(readlink "${XCODE_APPS_DIR}/Xcode.app")"
  [ ! -e "${XCODE_APPS_DIR}/Xcode_27.1.app/Xcode_27.2.app" ] || fail "ln followed the old link"
}

test_up_to_three_xcodes_are_all_warmed_once() {
  setup
  install_xcode 26.4.1 26.4
  install_xcode 27.1
  install_xcode 27.2
  select_xcode 27.2 >/dev/null
  : >"${work}/calls"
  warm_xcodes >/dev/null
  eq "sudo xcode-select -p" "$(head -1 "${work}/calls")"
  eq 3 "$(grep -c '^xcodebuild -version' "${work}/calls")"
  for v in 26.4.1 27.1 27.2; do
    grep -qx "xcodebuild -version ${XCODE_APPS_DIR}/Xcode_${v}.app/Contents/Developer" "${work}/calls" || fail "did not warm ${v}"
    grep -qx "xcodebuild -showsdks ${XCODE_APPS_DIR}/Xcode_${v}.app/Contents/Developer" "${work}/calls" || fail "no SDKs for ${v}"
    grep -qx "xcrun swift --version ${XCODE_APPS_DIR}/Xcode_${v}.app/Contents/Developer" "${work}/calls" || fail "no swift for ${v}"
  done
  [[ "$(calls)" != *"xcode-select -s"* ]] || fail "warm-up changed the selection"
  eq "${XCODE_APPS_DIR}/Xcode_27.2.app" "$(cat "${work}/selected")"
}

test_more_than_three_xcodes_warm_the_default_and_the_preferred() {
  setup
  for v in 26.3 26.5 26.6 27.0; do install_xcode "$v"; done
  # The default is reached through the Xcode.app link the image may carry.
  ln -s "${XCODE_APPS_DIR}/Xcode_26.6.app" "${XCODE_APPS_DIR}/Xcode.app"
  printf '%s' "${XCODE_APPS_DIR}/Xcode.app" >"${work}/selected"
  warm_xcodes 26.3 >/dev/null
  eq "xcodebuild -version ${XCODE_APPS_DIR}/Xcode_26.6.app/Contents/Developer
xcodebuild -version ${XCODE_APPS_DIR}/Xcode_26.3.app/Contents/Developer" "$(grep '^xcodebuild -version' "${work}/calls")"
}

test_more_than_three_xcodes_without_a_preference_warm_the_default() {
  setup
  for v in 26.3 26.5 26.6 27.0; do install_xcode "$v"; done
  printf '%s' "${XCODE_APPS_DIR}/Xcode_26.5.app" >"${work}/selected"
  warm_xcodes 26.5 >/dev/null
  eq "xcodebuild -version ${XCODE_APPS_DIR}/Xcode_26.5.app/Contents/Developer" "$(grep '^xcodebuild -version' "${work}/calls")"
}

test_the_warm_up_stops_at_the_claim() {
  setup
  install_xcode 27.1
  install_xcode 27.2
  STOP_AFTER_FIRST=1
  out=$(warm_xcodes)
  eq 1 "$(grep -c '^xcodebuild -version' "${work}/calls")"
  [[ "${out}" == *"warm-up stopped: claimed"* ]] || fail "unexpected output: ${out}"
}

for test in $(declare -F | awk '{print $3}' | grep '^test_'); do
  "$test"
  echo "ok: $test"
done
