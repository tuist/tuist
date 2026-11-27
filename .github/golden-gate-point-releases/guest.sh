#!/bin/bash
# Runs in a vanilla macOS guest: writes files into APFS images on the
# custom-cache share (the production cache volume format), into plain files
# on the share and onto the root disk, evicts the guest's cache, and counts
# the files that no longer match. ROUND only labels the output.
round="${1:-idle}"
share="/Volumes/My Shared Files/custom-cache"
ver="$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
sudo_() { printf 'admin\n' | sudo -S -p '' "$@"; }

src=/tmp/gg-src; rm -rf "$src"; mkdir -p "$src"
for i in $(seq 1 400); do head -c $((RANDOM % 6000 + 20)) /dev/urandom > "$src/f$i"; done
(cd "$src" && shasum -a 256 f*) > /tmp/gg-src.sum

check() {
  local bad
  bad=$(cd "$1" && shasum -a 256 -c /tmp/gg-src.sum 2>/dev/null | grep -vc ': OK$')
  echo "RESULT $ver $round | $2: bad=$bad of 400"
}
run_into() {
  local d="$1" l="$2"
  rm -rf "$d/cp" "$d/pc"; mkdir -p "$d/cp" "$d/pc"
  cp "$src"/f* "$d/cp/"; sync; sudo_ purge; check "$d/cp" "$l | cp after purge"
  (cd "$src" && ls | xargs -P 16 -I{} cp {} "$d/pc/{}"); check "$d/pc" "$l | parallel cp"
  sync; sudo_ purge; check "$d/pc" "$l | parallel cp after purge"
}

if [ "$round" = pressure ]; then
  memory_pressure -l warn > /tmp/gg-pressure.log 2>&1 &
  pressure=$!; trap 'kill $pressure 2>/dev/null' EXIT; sleep 20
fi

img="$share/x-$round"; mkdir -p "$img"
for n in 1 2 3; do
  f="$img/s$n.sparseimage"; m="/tmp/gg-m$n"; mkdir -p "$m"
  hdiutil create -size 100g -fs APFS -volname T -type SPARSE -quiet "$f" || { echo "RESULT $ver $round | sparseimage #$n: create failed"; continue; }
  if hdiutil attach "$f" -owners off -nobrowse -mountpoint "$m" -quiet; then
    run_into "$m" "sparseimage #$n on share"
    hdiutil detach "$m" -force -quiet
  else
    echo "RESULT $ver $round | sparseimage #$n: attach failed"
  fi
  rm -f "$f"
done
run_into "$img/plain" "plain files on share"
run_into "/tmp/gg-root" "root disk"
rm -rf "$img" /tmp/gg-root
