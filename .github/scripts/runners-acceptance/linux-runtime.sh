#!/usr/bin/env bash
# Exercise the deployed image as an ordinary, non-root Linux job.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
trap 'fail "Linux image/runtime" "a runtime assertion failed at line ${LINENO}"' ERR

test "$(id -u)" != 0
test "${ImageOS:-}" = ubuntu22
test -c /dev/kvm
test -r /dev/kvm
test -w /dev/kvm
printf 'set -e\necho login-shell-ready\nexit 0\n' | env SHLVL=0 /bin/bash --login

for executable in dispatch-poll.sh run-job.sh vitals.sh metrics-sampler.sh runner-shell-agent tuist-cache-volume tuist-gitlab-runner; do
  test -x "/usr/local/bin/${executable}"
done
test -x /home/runner/actions-runner/externals/tuist-cache-volume
for hook in environment pre-exit; do
  test -x "/usr/local/share/tuist/buildkite-hooks/${hook}"
done
buildkite-agent --version

test -n "${ANDROID_HOME:-}"
test "${ANDROID_SDK_ROOT:-}" = "$ANDROID_HOME"
test -f "$ANDROID_HOME/platforms/android-34/android.jar"
test -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
"$ANDROID_HOME/build-tools/34.0.0/aapt2" version
sdk_probe="$(mktemp "$ANDROID_HOME/.acceptance-XXXXXX")"
rm "$sdk_probe"

docker info >/dev/null
docker buildx version
docker compose version
curl --fail --silent --show-error --location --connect-timeout 5 --max-time 20 \
  --output /dev/null https://github.com
pass 'Linux image/runtime: non-root, KVM, login shell, executable clients/hooks, writable Android SDK, Docker and public HTTPS passed'
