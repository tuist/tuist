#!/bin/bash
# Experiment: on a freshly booted clone, time what a job pays to use each
# installed Xcode: selecting it, its first swift build, and booting a
# simulator on the iOS runtime matching its SDK. Prints BUNDLE-EXP lines.
set -uo pipefail
source ~/.zprofile 2>/dev/null || true

now() { python3 -c 'import time; print(f"{time.time():.1f}")' 2>/dev/null || date +%s; }
boot=$(sysctl -n kern.boottime | sed -E 's/.*sec = ([0-9]+).*/\1/')
echo "BUNDLE-EXP guest seconds from kernel boot to first command: $(( $(date +%s) - boot ))"
echo "BUNDLE-EXP disk used KiB: $(df -k / | awk 'NR==2 {print $3}')"

for app in $(ls -d /Applications/Xcode_*.app | sort); do
  [ -L "$app" ] && continue
  v=$(basename "$app" .app | sed 's/^Xcode_//')

  t0=$(now)
  sudo xcode-select -s "$app"
  xcodebuild -version >/dev/null
  t1=$(now)
  echo "BUNDLE-EXP $v select+version s: $(echo "$t1 - $t0" | bc)"

  dir=$(mktemp -d)
  (cd "$dir" && swift package init --type executable --name Hello >/dev/null 2>&1)
  t0=$(now)
  (cd "$dir" && swift build >/dev/null 2>&1) && ok=ok || ok=failed
  t1=$(now)
  echo "BUNDLE-EXP $v first swift build s: $(echo "$t1 - $t0" | bc) ($ok)"
  rm -rf "$dir"

  sdk=$(xcrun --sdk iphonesimulator --show-sdk-version 2>/dev/null)
  runtime=$(xcrun simctl list runtimes -j | jq -r --arg v "$sdk" '[.runtimes[] | select(.platform == "iOS" and .isAvailable and (.version | startswith($v)))][0].identifier // empty')
  dtype=$(xcrun simctl list devicetypes -j | jq -r '[.devicetypes[] | select(.productFamily == "iPhone")][-1].identifier')
  if [ -z "$runtime" ]; then
    echo "BUNDLE-EXP $v simulator: no iOS $sdk runtime"
    continue
  fi
  t0=$(now)
  udid=$(xcrun simctl create "exp-$v" "$dtype" "$runtime")
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 && ok=ok || ok=failed
  t1=$(now)
  echo "BUNDLE-EXP $v first simulator boot s (iOS $sdk): $(echo "$t1 - $t0" | bc) ($ok)"
  xcrun simctl shutdown "$udid" >/dev/null 2>&1
  t0=$(now)
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 && ok=ok || ok=failed
  t1=$(now)
  echo "BUNDLE-EXP $v second simulator boot s: $(echo "$t1 - $t0" | bc) ($ok)"
  xcrun simctl shutdown "$udid" >/dev/null 2>&1
  xcrun simctl delete "$udid" >/dev/null 2>&1
done
exit 0
