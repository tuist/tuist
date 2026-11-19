#!/usr/bin/env bash
# Step 4 proof on a disposable GitHub-hosted KVM VM: can a cache that a
# Linux CI job filled be attached to a Firecracker sandbox and reused there?
#
# 1. A CI-shaped job (Ubuntu 24.04, UID 1000 like the runner image's
#    `runner`) builds infra/sandboxd with GOMODCACHE and GOCACHE on an ext4
#    image made with runner-cache's mkfs flags.
# 2. Two sandboxes cold boot from the same disk snapshot: one builds with
#    empty caches, the other gets a private clone of the image as /dev/vdc.
# 3. The warm sandbox builds as `user` with the image's ownership unchanged
#    (unchanged source, then one edited package), then as UID 1000, then as
#    `user` after chown, all with GOPROXY=off.
#
# It records timings, compile counts and whether the master stayed intact.
# shellcheck disable=SC2016
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "${RUNNER_ENVIRONMENT:-}" == github-hosted ]] || {
  echo 'Run this only on a disposable GitHub-hosted Linux runner.' >&2
  exit 1
}
[[ $(uname -sm) == 'Linux x86_64' ]]
test -c /dev/kvm
repo=$(git rev-parse --show-toplevel)
work=$(mktemp -d "${RUNNER_TEMP:?}/cache-drive.XXXXXX")
evidence="$RUNNER_TEMP/cache-drive-evidence"
mkdir -p "$evidence" "$work/data" "$work/cache-mnt"
daemon="cache-drive-${GITHUB_RUN_ID:?}-${GITHUB_RUN_ATTEMPT:-1}"
go_version=1.26.10
go_url="https://go.dev/dl/go${go_version}.linux-amd64.tar.gz"
loop=''
cleanup() {
  local rc=$?
  trap - EXIT
  docker logs "$daemon" > "$evidence/sandboxd.log" 2>&1 || true
  docker rm -f "$daemon" >/dev/null 2>&1 || true
  if mountpoint -q "$work/cache-mnt"; then sudo umount "$work/cache-mnt" || rc=1; fi
  if mountpoint -q "$work/data"; then sudo umount "$work/data" || rc=1; fi
  if [[ -n "$loop" ]] && ! mountpoint -q "$work/data"; then sudo losetup -d "$loop" || rc=1; fi
  if ! mountpoint -q "$work/data"; then sudo rm -rf "$work"; fi
  exit "$rc"
}
trap cleanup EXIT
exec > >(tee "$evidence/cache-drive.log") 2>&1

# Production's strict FICLONE path: jails and cache images share one XFS.
truncate -s 40G "$work/data.xfs"
loop=$(sudo losetup --find --show "$work/data.xfs")
sudo mkfs.xfs -q -m reflink=1 "$loop"
sudo mount "$loop" "$work/data"
docker run --rm -v "$work/data:/host" -e TEMPLATE_TAG=validation sandbox-orbs-template:validation

# One Go toolchain, verified once, used by both sides so build cache keys match.
curl --fail --silent --show-error --location --retry 3 -o "$work/go.tgz" "$go_url"
go_sha=$(sha256sum "$work/go.tgz" | cut -d' ' -f1)
mkdir -p "$work/go-root"
tar -C "$work/go-root" -xzf "$work/go.tgz"
tar -C "$repo" -czf "$work/src.tgz" infra/sandboxd infra/runner-cache

# --- CI side --------------------------------------------------------------
cache_dir="$work/data/cache-images"
sudo mkdir -p "$cache_dir"
sudo truncate -s 8G "$cache_dir/go-cache"
# The same flags runner-cache uses for its masters (checkout_images.go).
sudo mkfs.ext4 -F -q -m 0 -i 65536 -L tuist-cache -E lazy_itable_init=0,lazy_journal_init=0,nodiscard "$cache_dir/go-cache"
sudo mount -o loop,noatime "$cache_dir/go-cache" "$work/cache-mnt"
sudo install -d -o 1000 -g 1000 "$work/cache-mnt/go"
mkdir -p "$work/src" && tar -C "$work/src" -xzf "$work/src.tgz"
ci_start=$(date +%s%N)
docker run --rm --network host --user 1000:1000 \
  -v "$work/go-root/go:/usr/local/go:ro" -v "$work/src:/src:ro" -v "$work/cache-mnt:/cache" \
  -v /etc/ssl/certs:/etc/ssl/certs:ro \
  -e HOME=/tmp -e GOTOOLCHAIN=local -e CGO_ENABLED=0 -e GOFLAGS="-buildvcs=false -mod=readonly" \
  -e GOMODCACHE=/cache/go/mod -e GOCACHE=/cache/go/build \
  -w /src/infra/sandboxd ubuntu:24.04@sha256:fe81560990fae86dc4743202b2cb4d3df98d0bcf949173cecef15ce1127ef852 \
  bash -euc '/usr/local/go/bin/go build -x ./... 2> /tmp/x; grep -c "/compile -o" /tmp/x' > "$evidence/ci-compiles.txt"
ci_ms=$(( ($(date +%s%N) - ci_start) / 1000000 ))
sudo du -sh "$work/cache-mnt/go/mod" "$work/cache-mnt/go/build" | tee "$evidence/ci-cache-size.txt"
sudo umount "$work/cache-mnt"
master_sha_before=$(sudo sha256sum "$cache_dir/go-cache" | cut -d' ' -f1)
echo "CI job filled the cache in ${ci_ms}ms with $(cat "$evidence/ci-compiles.txt") compiles"

# --- Sandbox side ---------------------------------------------------------
# Guests are always 10.0.0.2 (internal/network/addr.go). Some hosted
# runners resolve through 10.0.0.2 too, which a guest would answer itself,
# so the daemon gets public resolvers instead of the host's.
docker run -d --name "$daemon" --privileged --cgroupns=host --dns 1.1.1.1 --dns 8.8.8.8 \
  -v "$work/data:/data/sandboxes" -p 127.0.0.1:9471:9471 \
  -e ADMIN_ADDR=:9471 -e TEMPLATE_TAG=validation -e CACHE_IMAGE_DIR=/data/sandboxes/cache-images \
  -e BOOT_TIMEOUT=120s -e TEMPLATE_BOOT_TIMEOUT=180s -e SHUTDOWN_TIMEOUT=60s \
  sandbox-orbs-daemon:validation >/dev/null
for _ in {1..60}; do
  curl --silent --fail http://127.0.0.1:9471/healthz >/dev/null && break
  sleep 1
done
api() {
  local method=$1 path=$2
  shift 2
  curl --silent --show-error --fail-with-body --max-time 900 \
    -H 'content-type: application/json' -X "$method" "http://127.0.0.1:9471$path" "$@"
}
# guest ID SCRIPT: runs as root in the guest and prints stdout; fails on a non-zero exit.
guest() {
  local response
  # Through stdin: the base snapshot's script embeds the source tree, which
  # exceeds the kernel's 128 KiB limit for a single argument.
  response=$(printf '%s' "$2" | jq -Rsc '{cmd:["/bin/bash","-euc",.],timeout_ms:840000}' \
    | api POST "/v1/sandboxes/$1/exec" --data-binary @-)
  if ! jq -e '.exit_code == 0' <<< "$response" >/dev/null; then
    jq . <<< "$response"
    return 1
  fi
  jq -r '.stdout' <<< "$response"
}
create() {
  api POST /v1/sandboxes --data "$1" | tee "$evidence/create-$(jq -r .id <<< "$1").json"
  echo
}

# The base snapshot holds the same toolchain and source the CI job used,
# at the same paths, so cold and warm sandboxes differ only in the cache.
create '{"id":"base","template":"default","vcpus":2,"memory_mb":4096,"workspace_gb":1}'
# The guest agent runs each script as one bash argument, which the kernel
# caps at 128 KiB, so the source tree goes over in smaller pieces.
base64 -w0 "$work/src.tgz" | split -b 96K - "$work/src.b64."
for part in "$work"/src.b64.*; do
  guest base "printf '%s' '$(cat "$part")' >> /tmp/src.b64"
done
src_sha=$(sha256sum "$work/src.tgz" | cut -d' ' -f1)
# Guest egress is needed for the toolchain and the cold run's modules.
if ! guest base 'for _ in $(seq 60); do getent hosts go.dev proxy.golang.org && exit 0; sleep 1; done; exit 1'; then
  echo 'Guest DNS never resolved go.dev. Diagnostics:'
  guest base 'cat /etc/resolv.conf; ip -br addr; ip route; getent hosts ampcode.com || echo no-ampcode; getent ahosts go.dev || echo no-go.dev' || true
  cat /etc/resolv.conf
  exit 1
fi
guest base "curl --fail --silent --show-error --location --retry 3 -o /tmp/go.tgz '$go_url'
echo '$go_sha  /tmp/go.tgz' | sha256sum -c -
rm -rf /usr/local/go && tar -C /usr/local -xzf /tmp/go.tgz && rm /tmp/go.tgz
base64 -d /tmp/src.b64 > /tmp/src.tgz && rm /tmp/src.b64
echo '$src_sha  /tmp/src.tgz' | sha256sum -c -
mkdir -p /src && tar -C /src -xzf /tmp/src.tgz && rm /tmp/src.tgz && chown -R user:user /src
id user; uname -r"
api POST /v1/sandboxes/base/pause --data '{"sync_disks":true}' > "$evidence/pause-base.json"
api POST /v1/sandboxes/base/save_disks --data '{"snapshot_id":"go-src"}' > "$evidence/save-base.json"
api POST /v1/sandboxes/base/delete >/dev/null

# build USER GOMODCACHE GOCACHE: one timed `go build ./...` run as USER.
# Prints "<exit> <milliseconds> <compiles>"; never fails, so a refused cache is evidence.
build='build() {
  local start rc=0
  start=$(date +%s%N)
  runuser -u "$1" -- env HOME=/tmp GOTOOLCHAIN=local CGO_ENABLED=0 GOFLAGS="-buildvcs=false -mod=readonly" \
    GOMODCACHE="$2" GOCACHE="$3" ${4:+GOPROXY=$4} bash -c "cd /src/infra/sandboxd && /usr/local/go/bin/go build -x ./... 2> /tmp/x-$1" || rc=$?
  echo "$rc $(( ($(date +%s%N) - start) / 1000000 )) $(grep -c "/compile -o" /tmp/x-$1 || true)"
}'

create '{"id":"cold","template":"default","vcpus":2,"memory_mb":4096,"workspace_gb":1,"from_disk_snapshot":"go-src"}'
cold=$(guest cold "$build
mkdir -p /home/user/cold && chown user:user /home/user/cold
build user /home/user/cold/mod /home/user/cold/build")
api POST /v1/sandboxes/cold/delete >/dev/null
echo "cold sandbox: $cold"

create '{"id":"warm","template":"default","vcpus":2,"memory_mb":4096,"workspace_gb":1,"from_disk_snapshot":"go-src","cache_image":"go-cache"}'
guest warm 'lsblk -o NAME,SIZE,LABEL,MOUNTPOINT; blkid /dev/vdc' | tee "$evidence/warm-drives.txt"
warm=$(guest warm "$build
id -u runner >/dev/null 2>&1 || useradd --uid 1000 --no-create-home runner 2>/dev/null || true
ci_user=\$(getent passwd 1000 | cut -d: -f1)
mkdir -p /cache && mount -o noatime /dev/vdc /cache
echo \"as_is \$(build user /cache/go/mod /cache/go/build off)\"
# A real job changes some source, so the cache must also take new entries.
changed=/src/infra/sandboxd/internal/safepath/safepath.go
# An exported addition changes export data, so dependents recompile too. Go
# ignores cache write failures, so a cache it cannot write shows up only as
# the same work again on the next build.
cp \"\$changed\" /tmp/unchanged.go; echo 'func ChangedForCacheProof() {}' >> \"\$changed\"
echo \"as_is_changed \$(build user /cache/go/mod /cache/go/build off)\"
echo \"as_is_changed_again \$(build user /cache/go/mod /cache/go/build off)\"
cp /tmp/unchanged.go \"\$changed\"
echo \"uid1000_user \$ci_user\"
echo \"uid1000 \$(build \"\$ci_user\" /cache/go/mod /cache/go/build off)\"
start=\$(date +%s%N); chown -R user:user /cache/go; echo \"chown_ms \$(( (\$(date +%s%N) - start) / 1000000 ))\"
echo \"after_chown \$(build user /cache/go/mod /cache/go/build off)\"
echo 'func ChangedForCacheProof() {}' >> \"\$changed\"
echo \"after_chown_changed \$(build user /cache/go/mod /cache/go/build off)\"
echo \"after_chown_changed_again \$(build user /cache/go/mod /cache/go/build off)\"
cp /tmp/unchanged.go \"\$changed\"
echo \"guest_write \$(date +%s)\" > /cache/guest-write; sync")
echo "$warm" | tee "$evidence/warm.txt"
api POST /v1/sandboxes/warm/delete >/dev/null
sudo test ! -d "$work/data/jail/firecracker/warm"
master_sha_after=$(sudo sha256sum "$cache_dir/go-cache" | cut -d' ' -f1)

field() { awk -v k="$1" '$1 == k { $1 = ""; sub(/^ /, ""); print }' <<< "$warm"; }
jq -n \
  --arg ci_ms "$ci_ms" --arg ci_compiles "$(cat "$evidence/ci-compiles.txt")" \
  --arg cold "$cold" --arg as_is "$(field as_is)" --arg as_is_changed "$(field as_is_changed)" --arg as_is_again "$(field as_is_changed_again)" --arg uid1000_user "$(field uid1000_user)" \
  --arg uid1000 "$(field uid1000)" --arg chown "$(field chown_ms)" --arg after_chown "$(field after_chown)" --arg after_changed "$(field after_chown_changed)" --arg after_again "$(field after_chown_changed_again)" \
  --arg cold_boot "$(jq -r .boot_ms "$evidence/create-cold.json")" --arg warm_boot "$(jq -r .boot_ms "$evidence/create-warm.json")" \
  --argjson master_intact "$([[ $master_sha_before == "$master_sha_after" ]] && echo true || echo false)" \
  '{note: "exit milliseconds compiles", ci_job_fill: {ms: $ci_ms, compiles: $ci_compiles},
    sandbox_cold: $cold, sandbox_cache_as_is_as_user: $as_is,
    sandbox_cache_as_is_as_user_changed_source: {first: $as_is_changed, repeated: $as_is_again},
    sandbox_cache_as_uid_1000: {user: $uid1000_user, result: $uid1000},
    chown_ms: $chown, sandbox_cache_after_chown_as_user: $after_chown,
    sandbox_cache_after_chown_changed_source: {first: $after_changed, repeated: $after_again},
    boot_ms: {without_cache: $cold_boot, with_cache: $warm_boot}, master_intact: $master_intact}' \
  | tee "$evidence/cache-drive.json"
jq -e '.master_intact' "$evidence/cache-drive.json" >/dev/null
read -r rc _ compiles <<< "$(field after_chown)"
[[ $rc == 0 && $compiles == 0 ]] || { echo 'FAIL: the attached cache did not give a fully cached build'; exit 1; }
read -r rc _ compiles <<< "$(field after_chown_changed_again)"
[[ $rc == 0 && $compiles == 0 ]] || { echo 'FAIL: the attached cache did not keep new entries once owned by user'; exit 1; }
echo 'PASS: a CI-filled cache image attached to a cold-booted sandbox as a private drive.'
echo 'NOT COVERED: runner-cache master lifecycle, server placement, production node filesystems.'
