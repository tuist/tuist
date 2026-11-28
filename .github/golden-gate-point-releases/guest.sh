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

if [ "${round%%-*}" = pressure ]; then
  memory_pressure -l warn > /tmp/gg-pressure.log 2>&1 &
  pressure=$!; trap 'kill $pressure 2>/dev/null' EXIT; sleep 20
fi

img="$share/x-$round"; mkdir -p "$img"
# FORMATS lists the image kinds to try in turn, three of each, interleaved so
# every kind sees the same host load:
#   sparse     the production format, created on the share (the control)
#   udrw       read-write UDIF created on the guest's disk, copied to the share
#   udrw-share read-write UDIF created directly on the share
formats="${2:-sparse}"
make_image() { # kind n -> path
  case "$1" in
    sparse) hdiutil create -size 100g -fs APFS -volname T -type SPARSE -quiet "$img/s$2.sparseimage" && echo "$img/s$2.sparseimage" ;;
    udrw) diskutil image create blank --fs APFS --format UDRW --size 2G --volumeName T "/tmp/u$2.dmg" >/dev/null 2>&1 \
            && ditto "/tmp/u$2.dmg" "$img/u$2.dmg" && rm -f "/tmp/u$2.dmg" && echo "$img/u$2.dmg" ;;
    udrw-share) diskutil image create blank --fs APFS --format UDRW --size 2G --volumeName T "$img/w$2.dmg" >/dev/null 2>&1 && echo "$img/w$2.dmg" ;;
  esac
}
for n in 1 2 3; do
  for kind in $formats; do
    m="/tmp/gg-m-$kind-$n"; mkdir -p "$m"
    f=$(make_image "$kind" "$n") || { echo "RESULT $ver $round | $kind #$n: create failed"; continue; }
    t0=$(perl -MTime::HiRes=time -e 'printf "%.2f", time')
    if hdiutil attach "$f" -owners off -nobrowse -mountpoint "$m" -quiet; then
      t1=$(perl -MTime::HiRes=time -e 'printf "%.2f", time')
      echo "TIMING $ver $round | $kind #$n attach $(echo "$t1-$t0" | bc)s"
      run_into "$m" "$kind #$n on share"
      hdiutil detach "$m" -force -quiet
    else
      echo "RESULT $ver $round | $kind #$n: attach failed"
    fi
    rm -f "$f"
  done
done
run_into "$img/plain" "plain files on share"
run_into "/tmp/gg-root" "root disk"
rm -rf "$img" /tmp/gg-root
