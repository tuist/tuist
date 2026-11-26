#!/bin/bash
# Experiment: what the idle Xcode warm-up costs in memory. On a freshly
# booted clone, prints guest memory at three checkpoints: after boot, after
# the warm-up (WARM=none|one|all) and after a job-like swift build on the
# first Xcode. Each checkpoint holds for HOLD seconds so the host-side
# sampler in the workflow can read the VM's memory. Prints BUNDLE-EXP lines.
set -uo pipefail
source ~/.zprofile 2>/dev/null || true
WARM=${WARM:-none}
IMAGE=${IMAGE:-image}
HOLD=${HOLD:-30}
p="BUNDLE-EXP [$IMAGE warm=$WARM]"

apps=$(for a in /Applications/Xcode_*.app; do [ -L "$a" ] || echo "$a"; done | sort)
first=$(echo "$apps" | head -1)

guest_mem() {
  local page; page=$(sysctl -n hw.pagesize)
  vm_stat | awk -v pg="$page" -v tag="$1" -v p="$p" '
    /File-backed pages/ {fb=$3} /Pages free/ {fr=$3} /Pages active/ {ac=$3}
    /Pages wired down/ {wi=$4} /Anonymous pages/ {an=$3}
    END {mb=pg/1048576; printf "%s guest %s MB: file-backed %d, anonymous %d, active %d, wired %d, free %d\n", p, tag, fb*mb, an*mb, ac*mb, wi*mb, fr*mb}'
}

checkpoint() {
  sleep 5
  guest_mem "$1"
  echo "$p CHECKPOINT $1 start"
  sleep "$HOLD"
  echo "$p CHECKPOINT $1 end"
}

sleep 20
checkpoint boot

warm() {
  DEVELOPER_DIR="$1/Contents/Developer" xcodebuild -version >/dev/null
  DEVELOPER_DIR="$1/Contents/Developer" xcrun swift --version >/dev/null 2>&1
  DEVELOPER_DIR="$1/Contents/Developer" xcrun clang --version >/dev/null 2>&1
}
case "$WARM" in
  one) warm "$first" ;;
  all) for app in $apps; do warm "$app"; done ;;
esac
sudo -n xcode-select -s "$first"
xcrun simctl list runtimes >/dev/null 2>&1
checkpoint warm

export DEVELOPER_DIR="$first/Contents/Developer"
dir=$(mktemp -d)
(cd "$dir" && swift package init --type executable --name Hello >/dev/null 2>&1 && swift build >/dev/null 2>&1) && ok=ok || ok=failed
echo "$p swift build on $(basename "$first"): $ok"
rm -rf "$dir"
checkpoint job
exit 0
