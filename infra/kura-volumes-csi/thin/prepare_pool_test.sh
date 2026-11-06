#!/usr/bin/env bash
# Qualifies `kura-volumes-csi prepare-pool` against real LVM and device-mapper.
# Run only as root inside a disposable Linux VM: it creates one private sparse
# file, attaches its own loop device and a uniquely named volume group, and
# removes all of them on exit. Never point it at hosted nodes.
#
#   sudo env KURA_THIN_DISPOSABLE_VM=1 bash prepare_pool_test.sh /path/to/kura-volumes-csi
set -euo pipefail

[ "${KURA_THIN_DISPOSABLE_VM:-}" = 1 ] || { echo "set KURA_THIN_DISPOSABLE_VM=1 inside a disposable VM" >&2; exit 2; }
[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 2; }
bin="${1:?path to the kura-volumes-csi binary}"
[ -x "$bin" ] || { echo "$bin is not executable" >&2; exit 2; }

# The same LVM configuration the driver passes, so this harness and the
# binary see the loop device the same way.
lvmcfg='devices { use_devicesfile = 0 obtain_device_list_from_udev = 0 } activation { udev_sync = 0 udev_rules = 0 } backup { backup = 0 archive = 0 }'
lvm_() { "$1" --config "$lvmcfg" "${@:2}"; }

work="$(realpath "$(mktemp -d /var/tmp/kura-prepare-pool.XXXXXX)")"
vg="kpp$(od -An -N4 -tx4 /dev/urandom | tr -d ' ')"
pool=kura-thin
loop=""
cleanup() {
  set +e
  lvm_ vgremove -ff -y "$vg" >/dev/null 2>&1
  [ -n "$loop" ] && losetup -d "$loop"
  rm -rf "$work"
}
trap cleanup EXIT

truncate -s 24G "$work/disk"
loop="$(losetup --find --show "$work/disk")"
lvm_ pvcreate -q "$loop"
lvm_ vgcreate -q "$vg" "$loop"

state="$work/state"
mkdir -m 0700 "$state"
base=(prepare-pool --volume-group "$vg" --pool "$pool" --state-dir "$state" --data-size 16G --metadata-size 1G --max-volumes 128)

failures=0
check() { # name, condition result
  if [ "$2" = ok ]; then echo "PASS $1"; else echo "FAIL $1: $2"; failures=$((failures + 1)); fi
}
pool_report() {
  lvm_ lvs --noheadings --nosuffix --units b --separator '|' \
    -o lv_uuid,segtype,lv_size,lv_metadata_size,chunk_size,zero,discards,lv_when_full "$vg/$pool" | tr -d ' '
}
config_sum() { sha256sum "$state/thin-pool.json" | cut -d' ' -f1; }

# 1. A fresh pool from free extents, with the exact geometry and policy.
if out="$("$bin" "${base[@]}" 2>&1)"; then
  IFS='|' read -r uuid seg size meta chunk zero discards whenfull <<<"$(pool_report)"
  want="thin-pool|$((16 << 30))|$((1 << 30))|$((512 << 10))|zero|passdown|error"
  have="$seg|$size|$meta|$chunk|$zero|$discards|$whenfull"
  [ "$have" = "$want" ] && check "fresh pool geometry and policy" ok || check "fresh pool geometry and policy" "have $have, want $want"
  mode="$(stat -c %a "$state/thin-pool.json")"
  [ "$mode" = 600 ] && check "thin-pool.json is 0600" ok || check "thin-pool.json is 0600" "mode $mode"
  echo "result: $out"
  echo "thin-pool.json: $(cat "$state/thin-pool.json")"
else
  check "fresh pool" "exit $?: $out"
  exit 1
fi
sum="$(config_sum)"

# 2. An identical rerun changes nothing.
if out="$("$bin" "${base[@]}" 2>&1)"; then
  [ "$(pool_report | cut -d'|' -f1)" = "$uuid" ] && [ "$(config_sum)" = "$sum" ] &&
    check "identical rerun is a no-op" ok || check "identical rerun is a no-op" "pool or config changed"
else
  check "identical rerun is a no-op" "exit $?: $out"
fi

# 3. After deactivation and reactivation (what a reboot does; activation runs
#    thin_check), the pool is still accepted as prepared.
lvm_ vgchange -q -an "$vg"
lvm_ vgchange -q -ay "$vg"
if out="$("$bin" "${base[@]}" 2>&1)"; then
  check "rerun after reactivation" ok
else
  check "rerun after reactivation" "exit $?: $out"
fi

# 4. A different geometry is refused and leaves the pool alone.
args=("${base[@]}"); args[8]=12G
if out="$("$bin" "${args[@]}" 2>&1)"; then
  check "different data size is refused" "succeeded: $out"
else
  [ "$(pool_report | cut -d'|' -f1)" = "$uuid" ] && check "different data size is refused" ok ||
    check "different data size is refused" "pool changed"
  echo "  refusal: $out"
fi

# 5. A config that differs from the arguments is refused, not rewritten.
if out="$("$bin" "${base[@]}" --data-reserve 2G 2>&1)"; then
  check "different reserve is refused" "succeeded: $out"
else
  [ "$(config_sum)" = "$sum" ] && check "different reserve is refused" ok || check "different reserve is refused" "config rewritten"
  echo "  refusal: $out"
fi

# 6. A pool that already holds volumes but has no config is never adopted.
lvm_ lvcreate -q -V 1G -T "$vg/$pool" -n probe
orphan="$work/orphan"
mkdir -m 0700 "$orphan"
args=("${base[@]}"); args[6]="$orphan"
if out="$("$bin" "${args[@]}" 2>&1)"; then
  check "populated pool without config is refused" "succeeded: $out"
else
  [ ! -e "$orphan/thin-pool.json" ] && check "populated pool without config is refused" ok ||
    check "populated pool without config is refused" "wrote a config"
  echo "  refusal: $out"
fi

[ "$failures" = 0 ] || { echo "$failures check(s) failed"; exit 1; }
echo "all prepare-pool checks passed"
