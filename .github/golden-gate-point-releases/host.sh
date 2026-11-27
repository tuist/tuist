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
  local provision=()
  case "$image" in
    https://*)
      # A fresh install from Apple's restore image. macOS 27's first-boot
      # provisioning (Tart 2.33+, macOS 27 host and guest) creates the
      # vanilla images' admin user with SSH, as Cirrus's
      # vanilla-golden-gate template does, so no Setup Assistant clicks.
      tart create --from-ipsw "$image" --disk-size 50 "$vm" || return 1
      provision=(--provisioning-opts "fullName=Managed via Tart,username=admin,password=admin,logsInAutomatically=true,enablesRemoteLogin=true")
      ;;
    *) tart clone "$image" "$vm" || return 1 ;;
  esac
  # Builders have 16 GB: leave half of it to the host.
  tart set "$vm" --cpu 4 --memory 4096
  mkdir -p "$WORK/share-$vm" "$WORK/env-$vm"
  cp "$here/guest.sh" "$WORK/share-$vm/guest.sh"
  tart run "$vm" ${provision[@]+"${provision[@]}"} --no-graphics --no-audio --root-disk-opts caching=cached \
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

# pair A B runs the guest check in both VMs at once, twice: idle, then with
# each guest under its own memory pressure (guest.sh). Host-side
# memory_pressure got the job's step killed on a 16 GB builder.
pair() {
  local a="$1" b="$2" round
  for round in idle pressure; do
    gx "$a" "bash '/Volumes/My Shared Files/custom-cache/guest.sh' $round" > "$WORK/$a-$b-$round-a.log" 2>&1 &
    local ja=$!
    gx "$b" "bash '/Volumes/My Shared Files/custom-cache/guest.sh' $round" > "$WORK/$a-$b-$round-b.log" 2>&1 &
    local jb=$!
    wait "$ja" "$jb"
    sed -E "s/^RESULT /RESULT [$a with $b] /" "$WORK/$a-$b-$round-a.log" | grep '^RESULT' > "$WORK/$a-$b-$round.log"
    sed -E "s/^RESULT /RESULT [$b with $a] /" "$WORK/$a-$b-$round-b.log" | grep '^RESULT' >> "$WORK/$a-$b-$round.log"
    cat "$WORK/$a-$b-$round.log"
  done
}
