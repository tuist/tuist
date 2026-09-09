#!/usr/bin/env bash
# Runs only on a disposable macOS Actions runner: the test owns a temporary OS
# user and a temporary project on canary, and removes both on exit.
set -euo pipefail

run_as_test_user() {
  local tuist_binary="$1" artifacts="$2" project_name="$3"
  local fixture="$HOME/project" derived_data="$HOME/derived-data"
  local full_handle="tuist/$project_name" label="tuist.cache.tuist_$project_name"
  local socket="$HOME/.local/state/tuist/tuist_$project_name.sock"
  local project_created=0
  export CI=1 TUIST_FEATURE_FLAG_KURA=0

  # Invoked by the EXIT trap while this function's local variables are in scope.
  # shellcheck disable=SC2329
  cleanup_project() {
    local result=$?
    set +e
    cp "$HOME/.local/state/tuist/$label."*.log "$artifacts/" 2>/dev/null
    launchctl print "user/$(id -u)/$label" > "$artifacts/daemon-status.log" 2>&1
    "$tuist_binary" teardown cache --path "$fixture" > "$artifacts/cleanup-cache.log" 2>&1
    if [[ "$project_created" == 1 ]]; then
      if ! "$tuist_binary" project delete "$full_handle" --path "$fixture" > "$artifacts/cleanup-project.log" 2>&1; then
        echo "Failed to delete temporary canary project $full_handle"
        result=1
      fi
    fi
    exit "$result"
  }
  trap cleanup_project EXIT

  cd "$HOME"
  if launchctl print "gui/$(id -u)" > "$artifacts/gui-domain.log" 2>&1; then
    echo "The test user unexpectedly has a graphical login session"
    exit 1
  fi
  grep -Eq 'Domain does not support specified action|Could not find domain' "$artifacts/gui-domain.log"
  launchctl print "user/$(id -u)" > /dev/null
  echo "Confirmed: user $(id -u) has a background domain and no GUI domain"

  mkdir -p "$fixture/Sources"
  cat > "$fixture/Project.swift" <<'SWIFT'
import ProjectDescription

let project = Project(
    name: "HeadlessCacheE2E",
    targets: [
        .target(
            name: "HeadlessCacheE2E",
            destinations: .macOS,
            product: .commandLineTool,
            bundleId: "dev.tuist.headless-cache-e2e",
            sources: ["Sources/**"]
        )
    ]
)
SWIFT
  cat > "$fixture/Tuist.swift" <<SWIFT
import ProjectDescription

let tuist = Tuist(
    fullHandle: "$full_handle",
    url: "https://canary.tuist.dev",
    project: .tuist(generationOptions: .options(enableCaching: true))
)
SWIFT
  printf 'print("%s")\n' "$project_name" > "$fixture/Sources/main.swift"

  # These are the same canary test credentials used by the acceptance suites
  # in Project.swift. Authentication state stays in the temporary user's home.
  "$tuist_binary" auth login --email tuistrocks@tuist.dev --password tuistrocks \
    --url https://canary.tuist.dev > "$artifacts/auth.log" 2>&1
  "$tuist_binary" project create "$full_handle" --path "$fixture" --build-system xcode \
    > "$artifacts/project-create.log" 2>&1
  project_created=1

  if ! "$tuist_binary" setup cache --path "$fixture" > "$artifacts/setup.log" 2>&1; then
    /usr/bin/python3 - "$tuist_binary" "$full_handle" "$socket" > "$artifacts/foreground-daemon.log" 2>&1 <<'PYTHON'
import pathlib
import socket
import subprocess
import sys
import time

with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as probe:
    probe.setblocking(False)
    print("Native nonblocking Unix socket succeeded", flush=True)
process = subprocess.Popen([sys.argv[1], "cache-start", sys.argv[2], "--url", "https://canary.tuist.dev"])
try:
    for _ in range(100):
        if process.poll() is not None:
            print(f"Foreground daemon exited: {process.returncode}", flush=True)
            break
        if pathlib.Path(sys.argv[3]).is_socket():
            print("Foreground daemon socket became ready", flush=True)
            break
        time.sleep(0.1)
finally:
    if process.poll() is None:
        process.terminate()
    process.wait(timeout=10)
PYTHON
    exit 1
  fi
  local plist="$HOME/Library/LaunchAgents/$label.plist"
  [[ "$(plutil -extract LimitLoadToSessionType raw -o - "$plist")" == Background ]]
  [[ -S "$socket" ]]
  local first_pid
  first_pid=$(launchctl print "user/$(id -u)/$label" | awk '/^[[:space:]]*pid = / { print $3; exit }')
  [[ -n "$first_pid" ]]
  echo "Patched setup succeeded; Background LaunchAgent PID: $first_pid"

  "$tuist_binary" generate --path "$fixture" --no-open > "$artifacts/generate.log" 2>&1
  build() {
    local name="$1"
    "$tuist_binary" xcodebuild build --verbose \
      -project "$fixture/HeadlessCacheE2E.xcodeproj" -scheme HeadlessCacheE2E \
      -destination 'platform=macOS' -derivedDataPath "$derived_data" \
      "COMPILATION_CACHE_CAS_PATH=$HOME/cas-$name" \
      CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
      > "$artifacts/build-$name.log" 2>&1
    /usr/bin/python3 - "$derived_data/Logs/Build" > "$artifacts/cache-$name.log" <<'PYTHON'
import gzip
import pathlib
import re
import sys

for log in pathlib.Path(sys.argv[1]).glob("*.xcactivitylog"):
    data = gzip.decompress(log.read_bytes())
    for match in re.finditer(rb"(?:Swift|Clang) caching (?:query|materialize|upload) key[^\x00-\x1f]{0,160}|cache key query miss", data):
        print(match.group().decode("utf-8", errors="replace"))
PYTHON
  }
  build cold
  echo "Cold Xcode build succeeded"

  # Re-run setup to test replacing a real background daemon, then use an empty
  # local CAS at the SAME output path so subsequent hits must come from remote.
  "$tuist_binary" setup cache --path "$fixture" > "$artifacts/setup-again.log" 2>&1
  local second_pid
  second_pid=$(launchctl print "user/$(id -u)/$label" | awk '/^[[:space:]]*pid = / { print $3; exit }')
  [[ -n "$second_pid" && "$first_pid" != "$second_pid" ]]
  echo "Repeated setup replaced the daemon with PID: $second_pid"

  local hit=0 attempt
  for attempt in 1 2 3 4 5 6; do
    rm -rf "$derived_data"
    build "warm-$attempt"
    if grep -q 'caching query key' "$artifacts/cache-warm-$attempt.log" &&
      grep -q 'caching materialize key' "$artifacts/cache-warm-$attempt.log" &&
      ! grep -q 'cache key query miss' "$artifacts/cache-warm-$attempt.log"; then
      hit=1
      echo "Clean rebuild materialized cached compilation results with an empty local CAS and no remote misses"
      break
    fi
    sleep 10
  done
  [[ "$hit" == 1 ]]

  "$tuist_binary" teardown cache --path "$fixture" > "$artifacts/teardown.log" 2>&1
  if launchctl print "user/$(id -u)/$label" > /dev/null 2>&1; then
    echo "Teardown left the background LaunchAgent registered"
    exit 1
  fi
  [[ ! -e "$plist" && ! -S "$socket" ]]
  echo "Headless cache end-to-end test passed: setup, build, remote hits, replacement, teardown"
  exit 0
}

if [[ "${1:-}" == --user ]]; then
  shift
  run_as_test_user "$@"
fi

[[ "${GITHUB_ACTIONS:-}" == true ]] || { echo "Run this test on a disposable Actions runner"; exit 1; }
tuist_binary="${1:?Pass the built Tuist executable}"
artifacts="${2:?Pass an empty artifacts directory}"
test_user=tuist-cas-e2e
test_home="/Users/$test_user"
test_uid=7001
[[ -x "$tuist_binary" && ! -e "$test_home" && ! -e "$artifacts" ]]
if id "$test_user" > /dev/null 2>&1 || dscl . -search /Users UniqueID "$test_uid" | grep -q .; then
  echo "The temporary test user or UID already exists"
  exit 1
fi

cleanup_user() {
  local result=$?
  set +e
  sudo launchctl bootout "user/$test_uid" > /dev/null 2>&1
  sudo pkill -u "$test_uid" > /dev/null 2>&1
  sudo dscl . -delete "/Users/$test_user"
  sudo rm -rf "$test_home"
  exit "$result"
}
trap cleanup_user EXIT
sudo dscl . -create "/Users/$test_user"
sudo dscl . -create "/Users/$test_user" UniqueID "$test_uid"
sudo dscl . -create "/Users/$test_user" PrimaryGroupID 20
sudo dscl . -create "/Users/$test_user" NFSHomeDirectory "$test_home"
sudo dscl . -create "/Users/$test_user" UserShell /bin/bash
sudo dscl . -create "/Users/$test_user" AuthenticationAuthority ';DisabledUser;'
sudo mkdir -p "$test_home" "$artifacts"
sudo chown "$test_user:staff" "$test_home" "$artifacts"
sudo install -o "$test_user" -g staff -m 755 "$0" "$test_home/test.sh"
project_name="headless-$(uuidgen | tr '[:upper:]' '[:lower:]' | cut -c1-12)"
sudo launchctl asuser "$test_uid" sudo -H -u "$test_user" \
  /bin/bash "$test_home/test.sh" --user "$tuist_binary" "$artifacts" "$project_name"
