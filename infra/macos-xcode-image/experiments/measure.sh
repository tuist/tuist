#!/bin/bash
# Experiment: on a freshly booted clone, time what a job pays to use each
# installed Xcode. MODE=cold measures straight after boot; MODE=warm first
# runs the warm-up an idle warm runner would run, then measures. Prints
# BUNDLE-EXP lines prefixed with IMAGE and MODE.
set -uo pipefail
source ~/.zprofile 2>/dev/null || true
MODE=${MODE:-cold}
IMAGE=${IMAGE:-image}
p="BUNDLE-EXP [$IMAGE $MODE]"

now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time' 2>/dev/null || python3 -c 'import time; print(f"{time.time():.3f}")'; }
since() { echo "$(now) - $1" | bc; }

boot=$(sysctl -n kern.boottime | sed -E 's/^\{ sec = ([0-9]+),.*/\1/')
echo "$p seconds from kernel boot to first command: $(( $(date +%s) - boot ))"
t0=$(now); echo "$p timer overhead s: $(since "$t0")"

apps=$(for a in /Applications/Xcode_*.app; do [ -L "$a" ] || echo "$a"; done | sort)
echo "$p Xcodes: $(echo $apps)"

# The switch a claim would do: select, point Xcode.app at it, export DEVELOPER_DIR.
switch() {
  sudo -n xcode-select -s "$1"
  sudo -n ln -sfn "$1" /Applications/Xcode.app
  export DEVELOPER_DIR="$1/Contents/Developer"
}

if [ "$MODE" = warm ]; then
  t0=$(now)
  for app in $apps; do
    DEVELOPER_DIR="$app/Contents/Developer" xcodebuild -version >/dev/null
    DEVELOPER_DIR="$app/Contents/Developer" xcrun swift --version >/dev/null 2>&1
    DEVELOPER_DIR="$app/Contents/Developer" xcrun clang --version >/dev/null 2>&1
  done
  xcrun simctl list runtimes >/dev/null 2>&1
  echo "$p warm-up of all Xcodes s: $(since "$t0")"
fi

for app in $apps; do
  v=$(basename "$app" .app | sed 's/^Xcode_//')

  t0=$(now); switch "$app"; echo "$p $v switch only s: $(since "$t0")"
  t0=$(now); xcodebuild -version >/dev/null; echo "$p $v first xcodebuild -version s: $(since "$t0")"
  t0=$(now); xcodebuild -version >/dev/null; echo "$p $v second xcodebuild -version s: $(since "$t0")"

  dir=$(mktemp -d)
  (cd "$dir" && swift package init --type executable --name Hello >/dev/null 2>&1)
  t0=$(now)
  (cd "$dir" && swift build >/dev/null 2>&1) && ok=ok || ok=failed
  echo "$p $v first swift build s: $(since "$t0") ($ok)"
  rm -rf "$dir"
done

# Switching back and forth once everything has run, the steady-state cost.
for app in $apps; do
  v=$(basename "$app" .app | sed 's/^Xcode_//')
  t0=$(now); switch "$app"; xcodebuild -version >/dev/null
  echo "$p $v re-switch plus xcodebuild -version s: $(since "$t0")"
done
exit 0
