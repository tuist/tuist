#!/usr/bin/env bash
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'Run inside the Linux filesystem test container.' >&2; exit 1; }
script=$(realpath "$(dirname "$0")/provision-cache-filesystem.sh")
scratch=$(mktemp -d)
export PROVISION_TEST_ROOT="$scratch"
unit="tuist-cache-provision-test-$$.mount"
export PROVISION_TEST_UNIT="$unit"
trap 'rm -rf "$scratch"; rm -f "/etc/systemd/system/$unit"' EXIT
mkdir -p "$scratch/bin" /etc/systemd/system
cat > "$scratch/bin/tool" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
state=$PROVISION_TEST_ROOT
name=${0##*/}
printf '%s\n' "$name $*" >> "$state/calls"
case "$name" in
  df) printf 'Avail\n%s\n' "${PROVISION_TEST_AVAILABLE:-300000000000}" ;;
  fallocate) touch "${@: -1}" ;;
  mkfs.xfs) printf 'filesystem\n' > "${@: -1}" ;;
  stat) echo "${PROVISION_TEST_SIZE:-200000000000}" ;;
  systemd-escape) echo "$PROVISION_TEST_UNIT" ;;
  systemctl) [[ $1 != enable ]] || touch "$state/mounted" ;;
  findmnt)
    [[ -f "$state/mounted" ]] || exit 1
    [[ " $* " != *' SOURCE '* ]] || echo "${PROVISION_TEST_SOURCE:-/dev/loop-test}"
    ;;
  losetup) echo /dev/loop-test ;;
esac
SH
chmod +x "$scratch/bin/tool"
for tool in df fallocate mkfs.xfs stat systemd-escape systemctl findmnt losetup; do
  ln -s tool "$scratch/bin/$tool"
done
export PATH="$scratch/bin:$PATH"
root="$scratch/cache"
run() { bash "$script" "$root" 200 > "$scratch/output" 2>&1; }
reject() { if run; then echo "Expected refusal: $1" >&2; exit 1; fi; }

mkdir "$root"
echo existing > "$root/job-file"
reject 'nonempty directory'
[[ $(cat "$root/job-file") == existing ]]
! grep -q '^fallocate ' "$scratch/calls"
rm "$root/job-file"

export PROVISION_TEST_AVAILABLE=100000000000
reject 'insufficient reservation space'
[[ ! -e "$root.img" ]]
unset PROVISION_TEST_AVAILABLE

run
[[ $(cat "$root.img") == filesystem ]]
[[ $(grep -c '^mkfs.xfs ' "$scratch/calls") == 1 ]]
grep -q 'X-fstrim.notrim' "/etc/systemd/system/$unit"
run
[[ $(grep -c '^mkfs.xfs ' "$scratch/calls") == 1 ]]
[[ $(grep -c '^fallocate ' "$scratch/calls") == 1 ]]

export PROVISION_TEST_SIZE=100000000000
reject 'size change must never reformat or resize'
unset PROVISION_TEST_SIZE
export PROVISION_TEST_SOURCE=/dev/unrelated
reject 'foreign filesystem already mounted'
unset PROVISION_TEST_SOURCE
[[ $(cat "$root.img") == filesystem ]]
[[ $(grep -c '^mkfs.xfs ' "$scratch/calls") == 1 ]]

rm "$scratch/mounted"
mv "$root.img" "$scratch/original.img"
ln -s "$scratch/original.img" "$root.img"
reject 'symlink backing file'
[[ $(cat "$scratch/original.img") == filesystem ]]
echo 'Provisioning checks passed: cold setup, retry, nonempty directory, low space, size mismatch, foreign mount, symlink.'
