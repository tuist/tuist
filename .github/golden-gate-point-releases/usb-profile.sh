# Sourced by golden-gate-point-releases.yml after host.sh. usb_profile VM N
# boots VM from the 27.2 vanilla image with the patched Tart
# (tart@2.41.1-tuist.3, --usb-disk-requests) and hot-plugs a fresh 10 GB ASIF
# image N times, the way tart-kubelet does, without the server, the store or
# tuist-cache-volume. Each round prints, in seconds from the host's request:
#   tart       Tart answered .attached (Virtualization's controller.attach)
#   disk       the guest saw a new /dev/disk node
#   mounted    Disk Arbitration mounted the volume under /Volumes
#   detach     Tart answered .detached, after the guest unmounted it
usb_profile() {
  local vm="$1" rounds="$2" ptart="$WORK/tart-patched" req="$WORK/usb-requests" i
  mkdir -p "$ptart" "$req"
  curl -fsSL "https://github.com/tuist/tuist/releases/download/tart%402.41.1-tuist.3/tart.tar.gz" | tar -xz -C "$ptart" || return 1
  local bin; bin=$(find "$ptart" -type f -name tart -perm -u+x | head -1)
  [ -n "$bin" ] || { echo "RESULT usb: no tart binary in the release"; return 1; }
  "$bin" --version
  tart clone "$VANILLA:27.2" "$vm" && tart set "$vm" --cpu 4 --memory 4096 || return 1
  "$bin" run "$vm" --no-graphics --no-audio --root-disk-opts caching=cached \
    --usb-disk-requests "$req" > "$WORK/$vm.run.log" 2>&1 &
  reachable "$vm" || { tail -20 "$WORK/$vm.run.log"; return 1; }
  # Clock offset guest minus host, from the midpoint of one round trip.
  local h0 g h1 skew
  h0=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
  g=$(gx "$vm" "perl -MTime::HiRes=time -e 'printf \"%.3f\", time'" | tr -d '\r' | tail -1)
  h1=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
  skew=$(echo "$g - ($h0 + $h1) / 2" | bc -l); echo "guest clock offset ${skew}s (round trip $(echo "$h1 - $h0" | bc)s)"
  for i in $(seq 1 "$rounds"); do
    local img="$WORK/usb-$i.asif" vol="TuistProfile$i"
    diskutil image create blank --fs APFS --format ASIF --size 10G --volumeName "$vol" "$img" >/dev/null || { echo "RESULT usb #$i: create failed"; continue; }
    # The guest watches for the new disk and its mount and prints guest epochs.
    gx "$vm" "before=\$(ls /dev | grep -c '^disk'); disk=''; t=\$(date +%s); while [ \$(( \$(date +%s) - t )) -lt 120 ]; do now=\$(perl -MTime::HiRes=time -e 'printf \"%.3f\", time'); if [ -z \"\$disk\" ] && [ \$(ls /dev | grep -c '^disk') -gt \$before ]; then disk=\$now; echo DISK \$now; fi; if [ -d /Volumes/$vol ] && mount | grep -q \"/Volumes/$vol \"; then echo MOUNTED \$now; exit 0; fi; sleep 0.05; done; echo TIMEOUT" > "$WORK/usb-$i.guest" 2>&1 &
    local watcher=$!; sleep 3
    local t0 t1; t0=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
    printf '{"image":"%s"}' "$img" > "$req/.r$i.tmp" && mv "$req/.r$i.tmp" "$req/r$i.attach"
    while [ ! -e "$req/r$i.attached" ] && [ ! -e "$req/r$i.error" ]; do sleep 0.02; done
    t1=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
    [ -e "$req/r$i.error" ] && { echo "RESULT usb #$i: tart error $(cat "$req/r$i.error")"; wait "$watcher"; continue; }
    wait "$watcher"
    local gd gm; gd=$(sed -n 's/^DISK //p' "$WORK/usb-$i.guest" | tr -d '\r'); gm=$(sed -n 's/^MOUNTED //p' "$WORK/usb-$i.guest" | tr -d '\r')
    local d m
    d=$( [ -n "$gd" ] && echo "$gd - $skew - $t0" | bc -l | xargs printf '%.2f' || echo n/a)
    m=$( [ -n "$gm" ] && echo "$gm - $skew - $t0" | bc -l | xargs printf '%.2f' || echo n/a)
    gx "$vm" "diskutil unmount force /Volumes/$vol >/dev/null 2>&1; true"
    local t2 t3; t2=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
    : > "$req/.d$i.tmp" && mv "$req/.d$i.tmp" "$req/r$i.detach"
    while [ ! -e "$req/r$i.detached" ] && [ ! -e "$req/r$i.error" ]; do sleep 0.02; done
    t3=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
    echo "RESULT usb #$i: tart=$(echo "$t1 - $t0" | bc)s disk=${d}s mounted=${m}s detach=$(echo "$t3 - $t2" | bc)s"
    rm -f "$img"
  done
  tart stop "$vm" >/dev/null 2>&1; tart delete "$vm" >/dev/null 2>&1
}
