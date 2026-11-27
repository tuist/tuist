# Sourced by .github/workflows/golden-gate-point-releases.yml on the builder.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# gx VM COMMAND runs COMMAND in the guest through Tart's guest agent, or over
# SSH as the vanilla admin user when the image has no agent.
gx() {
  local vm="$1"; shift
  if [ "$(cat "$WORK/$vm.transport" 2>/dev/null)" = exec ]; then
    tart exec "$vm" /bin/bash -c "$*"
  else
    expect -f "$here/ssh.exp" "$(tart ip "$vm")" "$*"
  fi
}

# reachable VM waits until a command runs in the guest.
reachable() {
  local vm="$1" i
  for i in $(seq 1 60); do
    if tart exec "$vm" true >/dev/null 2>&1; then echo exec > "$WORK/$vm.transport"; return 0; fi
    if ip=$(tart ip "$vm" 2>/dev/null) && expect -f "$here/ssh.exp" "$ip" true >/dev/null 2>&1; then echo ssh > "$WORK/$vm.transport"; return 0; fi
    sleep 10
  done
  echo "RESULT $vm: unreachable" | tee -a "$WORK/$vm.log"; return 1
}

# boot VM IMAGE clones IMAGE and runs it the way tart-kubelet runs a runner VM:
# no graphics or audio, cached root disk, a read-only env share and the cache
# volume's directory as the custom-cache share.
boot() {
  local vm="$1" image="$2"
  tart clone "$image" "$vm"
  tart set "$vm" --cpu 4 --memory 8192
  mkdir -p "$WORK/share-$vm" "$WORK/env-$vm"
  cp "$here/guest.sh" "$WORK/share-$vm/guest.sh"
  tart run "$vm" --no-graphics --no-audio --root-disk-opts caching=cached \
    --dir "env:$WORK/env-$vm:ro" --dir "custom-cache:$WORK/share-$vm" > "$WORK/$vm.run.log" 2>&1 &
  reachable "$vm" || return 1
  gx "$vm" 'for i in $(seq 1 30); do [ -f "/Volumes/My Shared Files/custom-cache/guest.sh" ] && break; sleep 2; done; sw_vers; mount | grep -i virtio'
}

retire() { tart stop "$1" >/dev/null 2>&1; tart delete "$1" >/dev/null 2>&1; rm -rf "$WORK/share-$1" "$WORK/env-$1"; }

# update VM release|beta updates a 27.2 guest in place and waits for it to
# come back on the new release.
update() {
  local vm="$1" kind="$2" label before after i
  before=$(gx "$vm" 'sw_vers -productVersion' | tr -d '\r')
  if [ "$kind" = beta ]; then
    gx "$vm" 'printf "admin\n" | sudo -S -p "" /System/Library/PrivateFrameworks/Seeding.framework/Resources/seedutil enroll DeveloperSeed; printf "admin\n" | sudo -S -p "" /System/Library/PrivateFrameworks/Seeding.framework/Resources/seedutil current' 2>&1 | tee -a "$WORK/$vm.log"
  fi
  gx "$vm" 'softwareupdate --list 2>&1' | tee "$WORK/$vm.list"
  # A beta guest must be offered 27.3, not the 27.2.1 release update.
  if [ "$kind" = beta ]; then want='27\.3'; else want='27\.2\.1'; fi
  label=$(sed -n 's/^\* Label: \(macOS.*\)$/\1/p' "$WORK/$vm.list" | tr -d '\r' | grep -E "$want" | head -1)
  if [ -z "$label" ]; then echo "RESULT $vm: no $want update offered" | tee -a "$WORK/$vm.log"; return 1; fi
  echo "installing $label on $vm"
  gx "$vm" "printf 'admin\nadmin\n' | sudo -S -p '' softwareupdate -i '$label' -R --agree-to-license --user admin --stdinpass" 2>&1 | tail -20
  sleep 120
  for i in $(seq 1 100); do
    rm -f "$WORK/$vm.transport"
    if reachable "$vm" >/dev/null 2>&1; then
      after=$(gx "$vm" 'sw_vers -productVersion; sw_vers -buildVersion' 2>/dev/null | tr -d '\r' | paste -sd' ' -)
      case "$after" in "$before "*|"") ;; *) echo "RESULT $vm: updated $before -> $after"; return 0 ;; esac
    fi
    sleep 30
  done
  echo "RESULT $vm: update to $label did not apply" | tee -a "$WORK/$vm.log"; return 1
}

# pair A B runs the guest check in both VMs at once, then again under host
# memory pressure.
pair() {
  local a="$1" b="$2" round p
  for round in idle pressure; do
    p=""
    if [ "$round" = pressure ]; then memory_pressure -l warn > "$WORK/pressure.log" 2>&1 & p=$!; sleep 30; fi
    gx "$a" "bash '/Volumes/My Shared Files/custom-cache/guest.sh' $round" > "$WORK/$a-$b-$round-a.log" 2>&1 &
    local ja=$!
    gx "$b" "bash '/Volumes/My Shared Files/custom-cache/guest.sh' $round" > "$WORK/$a-$b-$round-b.log" 2>&1 &
    local jb=$!
    wait "$ja" "$jb"
    if [ -n "$p" ]; then kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; fi
    sed -E "s/^RESULT /RESULT [$a with $b] /" "$WORK/$a-$b-$round-a.log" | grep '^RESULT' > "$WORK/$a-$b-$round.log"
    sed -E "s/^RESULT /RESULT [$b with $a] /" "$WORK/$a-$b-$round-b.log" | grep '^RESULT' >> "$WORK/$a-$b-$round.log"
    cat "$WORK/$a-$b-$round.log"
  done
}
