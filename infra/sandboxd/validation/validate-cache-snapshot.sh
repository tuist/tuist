#!/usr/bin/env bash
# Experiment on a disposable GitHub-hosted KVM VM: can a cache image join a
# sandbox restored from the template's memory snapshot, instead of forcing
# the cold boot a disk-snapshot create takes today?
#
# With CACHE_DRIVE_IN_TEMPLATE=true, sandboxd snapshots each template shape
# with an empty 1 MiB cache drive. A create with cache_image clones the image
# into the jail in its place before restore and patches the drive, so the
# guest sees the new size. The guest agent's configure drops its /dev/vdc
# buffers, mounts it at /mnt/tuist-cache and binds the manifest's `~/` paths
# into the sandbox user's home; nothing in this script mounts it.
#
# Measured, each REPS times: template creates without the flag (control),
# with the flag and no cache, with the flag and a cache, and today's
# disk-snapshot cold create with a cache. Checked: the guest reads the
# image's bytes at the bound path as the sandbox user, can write to it, keeps
# it across pause and resume, a sandbox without a cache mounts nothing, and
# the master stays unchanged.
# shellcheck disable=SC2016
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "${RUNNER_ENVIRONMENT:-}" == github-hosted ]] || {
  echo 'Run this only on a disposable GitHub-hosted Linux runner.' >&2
  exit 1
}
[[ $(uname -sm) == 'Linux x86_64' ]]
test -c /dev/kvm
reps=${REPS:-5}
work=$(mktemp -d "${RUNNER_TEMP:?}/cache-snapshot.XXXXXX")
evidence="$RUNNER_TEMP/cache-snapshot-evidence"
mkdir -p "$evidence" "$work/data" "$work/cache-mnt"
daemon="cache-snapshot-${GITHUB_RUN_ID:?}-${GITHUB_RUN_ATTEMPT:-1}"
loop=''
cleanup() {
  local rc=$?
  trap - EXIT
  docker logs "$daemon" >> "$evidence/sandboxd.log" 2>&1 || true
  docker rm -f "$daemon" >/dev/null 2>&1 || true
  if mountpoint -q "$work/cache-mnt"; then sudo umount "$work/cache-mnt" || rc=1; fi
  if mountpoint -q "$work/data"; then sudo umount "$work/data" || rc=1; fi
  if [[ -n "$loop" ]] && ! mountpoint -q "$work/data"; then sudo losetup -d "$loop" || rc=1; fi
  if ! mountpoint -q "$work/data"; then sudo rm -rf "$work"; fi
  exit "$rc"
}
trap cleanup EXIT
exec > >(tee "$evidence/cache-snapshot.log") 2>&1

# Production's strict FICLONE path: jails and cache images share one XFS.
truncate -s 40G "$work/data.xfs"
loop=$(sudo losetup --find --show "$work/data.xfs")
sudo mkfs.xfs -q -m reflink=1 "$loop"
sudo mount "$loop" "$work/data"
# One copy of the template per daemon configuration, so the flag-on daemon
# cannot reuse shape snapshots built without the drive. Each is seeded just
# before its daemon starts, since startup deletes other tags.
docker run --rm -v "$work/data:/host" -e TEMPLATE_TAG=validation-off sandbox-orbs-template:validation

# A cache image made with runner-cache's mkfs flags, holding 256 MiB of
# random bytes owned by UID 1000 like a CI job's cache, in tuist-cache-volume's
# single-path layout: `data` and a manifest naming it `~/proof`.
cache_dir="$work/data/cache-images"
sudo mkdir -p "$cache_dir"
sudo truncate -s 8G "$cache_dir/proof-cache"
sudo mkfs.ext4 -F -q -m 0 -i 65536 -L tuist-cache -E lazy_itable_init=0,lazy_journal_init=0,nodiscard "$cache_dir/proof-cache"
sudo mount -o loop,noatime "$cache_dir/proof-cache" "$work/cache-mnt"
sudo install -d -o 1000 -g 1000 "$work/cache-mnt/data"
sudo head -c 256M /dev/urandom | sudo tee "$work/cache-mnt/data/blob" >/dev/null
sudo chown 1000:1000 "$work/cache-mnt/data/blob"
echo '{"version":1,"paths":{"~/proof":"data"}}' | sudo tee "$work/cache-mnt/.tuist-paths" >/dev/null
blob_sha=$(sudo sha256sum "$work/cache-mnt/data/blob" | cut -d' ' -f1)
sudo umount "$work/cache-mnt"
master_sha_before=$(sudo sha256sum "$cache_dir/proof-cache" | cut -d' ' -f1)

start_daemon() { # TAG IN_TEMPLATE
  docker rm -f "$daemon" >/dev/null 2>&1 || true
  # Guests are always 10.0.0.2 (internal/network/addr.go); see validate-cache-drive.sh.
  docker run -d --name "$daemon" --privileged --cgroupns=host --dns 1.1.1.1 --dns 8.8.8.8 \
    -v "$work/data:/data/sandboxes" -p 127.0.0.1:9471:9471 \
    -e ADMIN_ADDR=:9471 -e TEMPLATE_TAG="$1" -e CACHE_IMAGE_DIR=/data/sandboxes/cache-images \
    -e CACHE_DRIVE_IN_TEMPLATE="$2" \
    -e BOOT_TIMEOUT=120s -e TEMPLATE_BOOT_TIMEOUT=180s -e SHUTDOWN_TIMEOUT=60s \
    sandbox-orbs-daemon:validation >/dev/null
  for _ in {1..60}; do
    curl --silent --fail http://127.0.0.1:9471/healthz >/dev/null && return 0
    sleep 1
  done
  docker logs "$daemon"
  return 1
}
stop_daemon() {
  docker stop -t 90 "$daemon" >/dev/null
  docker logs "$daemon" >> "$evidence/sandboxd.log" 2>&1 || true
  docker rm "$daemon" >/dev/null
}
api() {
  local method=$1 path=$2
  shift 2
  curl --silent --show-error --fail-with-body --max-time 600 \
    -H 'content-type: application/json' -X "$method" "http://127.0.0.1:9471$path" "$@"
}
guest() { # ID SCRIPT: runs as root, prints stdout, fails on a non-zero exit.
  local response
  response=$(printf '%s' "$2" | jq -Rsc '{cmd:["/bin/bash","-euc",.],timeout_ms:300000}' \
    | api POST "/v1/sandboxes/$1/exec" --data-binary @-)
  if ! jq -e '.exit_code == 0' <<< "$response" >/dev/null; then
    jq . <<< "$response"
    return 1
  fi
  jq -r '.stdout' <<< "$response"
}
# create CASE ID BODY: records the daemon's boot_ms and the client's wall time.
create() {
  local start response
  start=$(date +%s%N)
  response=$(api POST /v1/sandboxes --data "$3")
  echo "$1 $2 $(jq -r .boot_ms <<< "$response") $(( ($(date +%s%N) - start) / 1000000 ))" | tee -a "$evidence/creates.txt"
}
shape='"template":"default","vcpus":2,"memory_mb":4096,"workspace_gb":1'
build_shape() {
  api POST /v1/templates/default/"$1"/build --data '{"vcpus":2,"memory_mb":4096}' | tee -a "$evidence/template-builds.txt"
  echo
}
# What the guest's own configure left: the drive at /mnt/tuist-cache, `data`
# bound at ~/proof and handed to the sandbox user. Prints facts.
mount_check='echo "size $(blockdev --getsize64 /dev/vdc)"
echo "mounted $(findmnt -n -o SOURCE,OPTIONS /mnt/tuist-cache)"
echo "bound $(findmnt -n -o SOURCE /home/user/proof)"
echo "owner $(stat -c %U:%G /home/user/proof /home/user/proof/blob | tr "\n" " ")"
echo "blob $(setpriv --reuid=user --regid=user --clear-groups sha256sum /home/user/proof/blob | cut -d" " -f1)"
setpriv --reuid=user --regid=user --clear-groups touch /home/user/proof/user-write && echo "user_write ok"'
check_mount() { # ID OUTPUT
  [[ $(field blob "$2") == "$blob_sha" ]] || { echo "$1 read the wrong bytes"; echo "$2"; exit 1; }
  [[ $(field mounted "$2") == '/dev/vdc '*noatime* ]] || { echo "$1 has no guest cache mount"; echo "$2"; exit 1; }
  [[ $(field bound "$2") == '/dev/vdc[/data]' ]] || { echo "$1 has no ~/proof bind"; echo "$2"; exit 1; }
  [[ $(field owner "$2") == 'user:user user:user' ]] || { echo "$1 left the cache to the wrong owner"; echo "$2"; exit 1; }
  [[ $(field user_write "$2") == ok ]] || { echo "$1 cache is not writable by the user"; echo "$2"; exit 1; }
}
field() { awk -v k="$1" '$1 == k { $1 = ""; sub(/^ /, ""); print }' <<< "$2"; }

# --- Control: today's daemon, no placeholder ------------------------------
start_daemon validation-off false
build_shape validation-off
for i in $(seq "$reps"); do
  create control "control-$i" "{\"id\":\"control-$i\",$shape}"
  guest "control-$i" 'lsblk -dn -o NAME' | tr '\n' ' ' > "$evidence/control-drives.txt"
  api POST "/v1/sandboxes/control-$i/delete" >/dev/null
done
echo "control drives: $(cat "$evidence/control-drives.txt")"
if api POST /v1/sandboxes --data "{\"id\":\"refused\",$shape,\"cache_image\":\"proof-cache\"}" > "$evidence/refused.json"; then
  echo 'A template create without a placeholder accepted a cache image.'
  exit 1
fi
cat "$evidence/refused.json"; echo
stop_daemon

# --- Placeholder in the template snapshot ---------------------------------
docker run --rm -v "$work/data:/host" -e TEMPLATE_TAG=validation sandbox-orbs-template:validation
start_daemon validation true
build_shape validation
sudo find "$work/data" -path '*/default/validation/*/2x4096/metadata.json' -exec cat {} \; | tee "$evidence/shape-metadata.json"
echo
for i in $(seq "$reps"); do
  create placeholder "placeholder-$i" "{\"id\":\"placeholder-$i\",$shape}"
  guest "placeholder-$i" 'echo "vdc $(blockdev --getsize64 /dev/vdc)"; echo "workspace $(findmnt -n -o SOURCE /workspace)"
mountpoint -q /mnt/tuist-cache && echo "cache mounted" || echo "cache none"' > "$evidence/placeholder-guest.txt"
  grep -qx 'cache none' "$evidence/placeholder-guest.txt" || { echo "placeholder-$i mounted its blank placeholder"; exit 1; }
  api POST "/v1/sandboxes/placeholder-$i/delete" >/dev/null
done
cat "$evidence/placeholder-guest.txt"

for i in $(seq "$reps"); do
  create snapshot_cache "warm-$i" "{\"id\":\"warm-$i\",$shape,\"cache_image\":\"proof-cache\"}"
  out=$(guest "warm-$i" "$mount_check")
  echo "$out" > "$evidence/warm-$i.txt"
  check_mount "warm-$i" "$out"
  [[ $(field size "$out") == $((8 << 30)) ]] || { echo "warm-$i saw the wrong size"; echo "$out"; exit 1; }
  if [[ $i == 1 ]]; then
    # Writable, and kept across pause and resume (a snapshot of the sandbox
    # itself, which now records the real image).
    guest warm-1 'echo guest-write > /home/user/proof/guest-write && sync'
    api POST /v1/sandboxes/warm-1/pause --data '{}' > "$evidence/pause-warm.json"
    api POST /v1/sandboxes/warm-1/resume --data '{}' > "$evidence/resume-warm.json"
    resumed=$(guest warm-1 'cat /home/user/proof/guest-write; findmnt -n -o SOURCE /home/user/proof; sha256sum /home/user/proof/blob | cut -d" " -f1; findmnt -n /mnt/tuist-cache | wc -l')
    echo "$resumed" | tee "$evidence/warm-resumed.txt"
    # One mount after the resume's configure, not a second on top.
    [[ $(sed -n 1p <<< "$resumed") == guest-write && $(sed -n 2p <<< "$resumed") == '/dev/vdc[/data]' && $(sed -n 3p <<< "$resumed") == "$blob_sha" && $(sed -n 4p <<< "$resumed") == 1 ]]
  fi
  api POST "/v1/sandboxes/warm-$i/delete" >/dev/null
done

# --- Today's path: disk snapshot plus a cold boot -------------------------
create base base "{\"id\":\"base\",$shape}"
api POST /v1/sandboxes/base/pause --data '{"sync_disks":true}' > "$evidence/pause-base.json"
api POST /v1/sandboxes/base/save_disks --data '{"snapshot_id":"base"}' > "$evidence/save-base.json"
api POST /v1/sandboxes/base/delete >/dev/null
for i in $(seq "$reps"); do
  create cold_cache "cold-$i" "{\"id\":\"cold-$i\",$shape,\"from_disk_snapshot\":\"base\",\"cache_image\":\"proof-cache\"}"
  out=$(guest "cold-$i" "$mount_check")
  echo "$out" > "$evidence/cold-$i.txt"
  check_mount "cold-$i" "$out"
  api POST "/v1/sandboxes/cold-$i/delete" >/dev/null
done
stop_daemon
sudo test ! -e "$work/data/jail/firecracker/warm-1"
master_sha_after=$(sudo sha256sum "$cache_dir/proof-cache" | cut -d' ' -f1)

median() { sort -n | awk '{ a[NR] = $1 } END { print (NR % 2 ? a[(NR + 1) / 2] : (a[NR / 2] + a[NR / 2 + 1]) / 2) }'; }
summary=$(for c in control placeholder snapshot_cache cold_cache; do
  boot=$(awk -v c="$c" '$1 == c { print $3 }' "$evidence/creates.txt" | median)
  wall=$(awk -v c="$c" '$1 == c { print $4 }' "$evidence/creates.txt" | median)
  jq -n --arg c "$c" --argjson boot "$boot" --argjson wall "$wall" '{case: $c, median_boot_ms: $boot, median_create_wall_ms: $wall}'
done | jq -s .)
jq -n --argjson cases "$summary" --arg reps "$reps" \
  --argjson master_intact "$([[ $master_sha_before == "$master_sha_after" ]] && echo true || echo false)" \
  '{reps: $reps, cases: $cases, master_intact: $master_intact}' \
  | tee "$evidence/summary.json"
jq -e '.master_intact' "$evidence/summary.json" >/dev/null
