#!/bin/sh
# Print a guest preparation script embedding the existing, small iOS fixture.
# No downloads or host mounts inside the guest. Run this generator on macOS.
set -eu
repo_root=$(cd "$(dirname "$0")/../../../.." && pwd)
archive=$(mktemp /tmp/tuist-resume-fixture.XXXXXX)
trap 'rm -f "$archive"' EXIT HUP INT TERM
tar -czf "$archive" -C "$repo_root/cli/Tests/Fixtures" Frameworks
cat <<'SCRIPT'
set -eu
mkdir -p /tmp/tuist-resume-fixture
SCRIPT
printf 'printf %%s '
base64 -i "$archive" | tr -d '\n'
printf ' | base64 -D | tar -xz -C /tmp/tuist-resume-fixture\n'
cat <<'SCRIPT'
xcodebuild -version
sim=$(xcrun simctl create TuistResumeBenchmark com.apple.CoreSimulator.SimDeviceType.iPhone-16)
xcrun simctl boot "$sim"
xcrun simctl bootstatus "$sim" -b
printf '%s\n' "$sim" > /tmp/tuist-resume-fixture/simulator
SCRIPT
