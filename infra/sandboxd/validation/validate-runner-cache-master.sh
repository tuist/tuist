#!/usr/bin/env bash
# Step 4 proof with a runner-cache master instead of a script-built image, on
# a disposable GitHub-hosted KVM VM.
#
# 1. cachemaster drives runner-cache's LocalImages: attach a new lineage,
#    run the job, then Seal verifies and publishes it and installs
#    masters/<scope>/<generation>-<digest>.img. Only the object store is a
#    stand-in.
# 2. The job is the published Linux runner image as `runner` (UID 1000). Like
#    `.github/actions/cache-volume` with `~/go/pkg/mod` and `~/.cache/go-build`,
#    it gets the client's two-path layout (a `.tuist-paths` manifest and one
#    sha256-named directory per spelling) bind-mounted at those paths, Go
#    where setup-go installs it, and the source at the job workspace path.
# 3. The unmodified master is attached to three sandboxes cloned from one
#    disk snapshot: no cache; the cache at the sandbox user's own paths
#    (mounted and bound by the guest agent's configure, then checked again
#    after a pause and resume); and at the runner's paths, toolchain and
#    workspace (what a CI-parity template with the runner's checkout path
#    would give, rebound by hand on top of the guest's mount).
#
# Scenario outcomes are recorded, not asserted: they are the result.
# shellcheck disable=SC2016
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "${RUNNER_ENVIRONMENT:-}" == github-hosted ]] || {
  echo 'Run this only on a disposable GitHub-hosted Linux runner.' >&2
  exit 1
}
[[ $(uname -sm) == 'Linux x86_64' ]]
test -c /dev/kvm
repo=$(git rev-parse --show-toplevel)
work=$(mktemp -d "${RUNNER_TEMP:?}/runner-master.XXXXXX")
evidence="$RUNNER_TEMP/runner-master-evidence"
mkdir -p "$evidence" "$work/data"
daemon="runner-master-${GITHUB_RUN_ID:?}-${GITHUB_RUN_ATTEMPT:-1}"
runner_image=${RUNNER_IMAGE:-ghcr.io/tuist/tuist-linux-runner@sha256:a97039dd946177866b819f256613469fd1f13c45b95d460b6ae6f16b7cd0c22d}
go_version=1.26.10
go_url="https://go.dev/dl/go${go_version}.linux-amd64.tar.gz"
# The Actions runner's tool cache under the job work directory (run-job.sh
# --builds-dir), where setup-go installs; and the job's workspace.
runner_goroot=/home/runner/work/_tool/go/$go_version/x64
runner_src=/home/runner/work/tuist/tuist
loop=''
cleanup() {
  local rc=$?
  trap - EXIT
  docker logs "$daemon" > "$evidence/sandboxd.log" 2>&1 || true
  docker rm -f "$daemon" >/dev/null 2>&1 || true
  if mountpoint -q "$work/data/job"; then sudo umount "$work/data/job" || rc=1; fi
  if mountpoint -q "$work/data"; then sudo umount "$work/data" || rc=1; fi
  if [[ -n "$loop" ]] && ! mountpoint -q "$work/data"; then sudo losetup -d "$loop" || rc=1; fi
  if ! mountpoint -q "$work/data"; then sudo rm -rf "$work"; fi
  exit "$rc"
}
trap cleanup EXIT
exec > >(tee "$evidence/runner-master.log") 2>&1

truncate -s 60G "$work/data.xfs"
loop=$(sudo losetup --find --show "$work/data.xfs")
sudo mkfs.xfs -q -m reflink=1 "$loop"
sudo mount "$loop" "$work/data"
docker run --rm -v "$work/data:/host" -e TEMPLATE_TAG=validation sandbox-orbs-template:validation

curl --fail --silent --show-error --location --retry 3 -o "$work/go.tgz" "$go_url"
go_sha=$(sha256sum "$work/go.tgz" | cut -d' ' -f1)
mkdir -p "$work/go-root" "$work/src"
tar -C "$work/go-root" -xzf "$work/go.tgz"
tar -C "$repo" -czf "$work/src.tgz" infra/sandboxd infra/runner-cache
tar -C "$work/src" -xzf "$work/src.tgz"
(cd "$repo/infra/sandboxd" && GOWORK=off GOTOOLCHAIN=local "$work/go-root/go/bin/go" build -o "$work/cachemaster" ./validation/cachemaster)
docker pull --quiet "$runner_image"

# --- The CI job, on a runner-cache branch --------------------------------
cat > "$work/job.sh" <<JOB
#!/usr/bin/env bash
set -euo pipefail
volume=\$TUIST_VOLUME_MOUNT
mod=\$(printf %s '~/go/pkg/mod' | sha256sum | cut -c1-64)
build=\$(printf %s '~/.cache/go-build' | sha256sum | cut -c1-64)
# What tuist-cache-volume, running as the job user, leaves for two paths:
# sha256-named directories and a manifest keyed by their spellings
# (manifest.go). Made as root and handed to UID 1000, because this host's
# temporary directory is under a home UID 1000 cannot enter.
install -d -o 1000 -g 1000 -m 0755 "\$volume/\$mod" "\$volume/\$build"
printf '{"version":1,"paths":{"~/.cache/go-build":"%s","~/go/pkg/mod":"%s"}}\n' "\$build" "\$mod" > "\$volume/.tuist-paths"
chown 1000:1000 "\$volume/.tuist-paths" && chmod 0644 "\$volume/.tuist-paths"
start=\$(date +%s%N)
docker run --rm --network host --user 1000:1000 \\
  -v '$work/go-root/go:$runner_goroot:ro' -v '$work/src:$runner_src:ro' \\
  -v "\$volume/\$mod:/home/runner/go/pkg/mod" -v "\$volume/\$build:/home/runner/.cache/go-build" \\
  -e HOME=/home/runner -e GOTOOLCHAIN=local -w '$runner_src/infra/sandboxd' '$runner_image' \\
  bash -euc 'export PATH=$runner_goroot/bin:\$PATH
    go env GOROOT GOMODCACHE GOCACHE CGO_ENABLED > /tmp/env
    echo "gcc \$(command -v gcc || echo none)" >> /tmp/env
    go build -x ./... 2> /tmp/x
    cat /tmp/env; echo "compiles \$(grep -c "/compile -o" /tmp/x)"' > '$evidence/job.txt'
echo "ms \$(( (\$(date +%s%N) - start) / 1000000 ))" >> '$evidence/job.txt'
JOB
chmod +x "$work/job.sh"
master=$(sudo PATH="/usr/sbin:/sbin:$PATH" "$work/cachemaster" -root "$work/data/runner-cache" -mount "$work/data/job" -- "$work/job.sh")
cat "$evidence/job.txt"
sudo ls -la "$(dirname "$master")" | tee "$evidence/master-listing.txt"
sudo cat "$master.json" > "$evidence/master-metadata.json" 2>/dev/null || true
# The same file, not a copy: sandboxd clones the master itself.
sudo mkdir -p "$work/data/cache-images"
sudo ln "$master" "$work/data/cache-images/runner-master"
master_sha_before=$(sudo sha256sum "$master" | cut -d' ' -f1)

# --- Sandboxes ------------------------------------------------------------
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
# guest ID SCRIPT: runs as root in the guest, prints stdout, fails on a
# non-zero exit. The script goes through stdin, not an argument.
guest() {
  local response
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

create '{"id":"base","template":"default","vcpus":2,"memory_mb":4096,"workspace_gb":1}'
# The agent runs each script as one bash argument, capped at 128 KiB.
base64 -w0 "$work/src.tgz" | split -b 96K - "$work/src.b64."
for part in "$work"/src.b64.*; do
  guest base "printf '%s' '$(cat "$part")' >> /tmp/src.b64"
done
if ! guest base 'for _ in $(seq 60); do getent hosts go.dev proxy.golang.org && exit 0; sleep 1; done; exit 1'; then
  guest base 'cat /etc/resolv.conf; ip route' || true
  exit 1
fi
src_sha=$(sha256sum "$work/src.tgz" | cut -d' ' -f1)
guest base "curl --fail --silent --show-error --location --retry 3 -o /tmp/go.tgz '$go_url'
echo '$go_sha  /tmp/go.tgz' | sha256sum -c -
base64 -d /tmp/src.b64 > /tmp/src.tgz && echo '$src_sha  /tmp/src.tgz' | sha256sum -c -
rm -rf /usr/local/go && tar -C /usr/local -xzf /tmp/go.tgz
mkdir -p /home/user/workspace/tuist '$runner_src' '$(dirname "$runner_goroot")'
tar -C /home/user/workspace/tuist -xzf /tmp/src.tgz && chown -R user:user /home/user/workspace
cp -a /usr/local/go '$runner_goroot'
tar -C '$runner_src' -xzf /tmp/src.tgz
chown -R 1000:1000 /home/runner
rm /tmp/go.tgz /tmp/src.tgz /tmp/src.b64
echo \"user \$(id -u user); uid1000 \$(getent passwd 1000 | cut -d: -f1); gcc \$(command -v gcc || echo none)\"" | tee "$evidence/guest.txt"
api POST /v1/sandboxes/base/pause --data '{"sync_disks":true}' > "$evidence/pause-base.json"
api POST /v1/sandboxes/base/save_disks --data '{"snapshot_id":"go-src"}' > "$evidence/save-base.json"
api POST /v1/sandboxes/base/delete >/dev/null

# build UID HOME GOROOT SRC [GOPROXY]: a timed `go build ./...` with Go's
# default cache locations under HOME. Prints "<exit> <ms> <compiles> <CGO_ENABLED>".
build='build() {
  local start rc=0 cgo
  cgo=$(setpriv --reuid="$1" --regid="$1" --clear-groups env -i PATH="$3/bin:/usr/bin:/bin" HOME="$2" GOTOOLCHAIN=local go env CGO_ENABLED)
  start=$(date +%s%N)
  setpriv --reuid="$1" --regid="$1" --clear-groups env -i PATH="$3/bin:/usr/bin:/bin" HOME="$2" GOTOOLCHAIN=local ${5:+GOPROXY=$5} \
    bash -c "cd $4/infra/sandboxd && go build -x ./... 2> /tmp/x-$1" || rc=$?
  echo "$rc $(( ($(date +%s%N) - start) / 1000000 )) $(grep -c "/compile -o" /tmp/x-$1 || true) $cgo"
}
user=$(id -u user)'
# mount_cache HOME OWNER: binds each manifest path of the guest's cache
# mount under HOME, for a home other than the sandbox user's.
mount_cache='mount_cache() {
  mountpoint -q /mnt/tuist-cache
  local spelling dir start
  for spelling in "~/go/pkg/mod" "~/.cache/go-build"; do
    dir=$(printf %s "$spelling" | sha256sum | cut -c1-64)
    grep -qF "\"$spelling\":\"$dir\"" /mnt/tuist-cache/.tuist-paths
    test -d "/mnt/tuist-cache/$dir"
    mkdir -p "$1/${spelling#\~/}"
    mount --bind "/mnt/tuist-cache/$dir" "$1/${spelling#\~/}"
  done
  start=$(date +%s%N)
  chown -R "$2" "/mnt/tuist-cache/$(printf %s "~/go/pkg/mod" | sha256sum | cut -c1-64)" "/mnt/tuist-cache/$(printf %s "~/.cache/go-build" | sha256sum | cut -c1-64)"
  echo "chown_ms $(( ($(date +%s%N) - start) / 1000000 ))"
}'

create '{"id":"cold","template":"default","vcpus":2,"memory_mb":4096,"workspace_gb":1,"from_disk_snapshot":"go-src"}'
cold=$(guest cold "if mountpoint -q /mnt/tuist-cache; then exit 1; fi
$build
build \$user /home/user /usr/local/go /home/user/workspace/tuist")
api POST /v1/sandboxes/cold/delete >/dev/null
echo "cold: $cold"

create '{"id":"sandboxpaths","template":"default","vcpus":2,"memory_mb":4096,"workspace_gb":1,"from_disk_snapshot":"go-src","cache_image":"runner-master"}'
# Nothing here mounts: configure did, on create and again on resume.
guest_mounts='for t in /mnt/tuist-cache /home/user/go/pkg/mod /home/user/.cache/go-build; do findmnt -n -o TARGET,SOURCE,OPTIONS --mountpoint "$t"; done
stat -c "%n %U:%G" /home/user/go /home/user/go/pkg/mod /home/user/.cache/go-build
echo "foreign $(find /home/user/go/pkg/mod /home/user/.cache/go-build ! -user user | wc -l)"'
guest sandboxpaths "$guest_mounts" | tee "$evidence/sandboxpaths-mounts.txt"
api POST /v1/sandboxes/sandboxpaths/pause --data '{}' > "$evidence/pause-sandboxpaths.json"
api POST /v1/sandboxes/sandboxpaths/resume --data '{}' > "$evidence/resume-sandboxpaths.json"
guest sandboxpaths "$guest_mounts" | tee "$evidence/sandboxpaths-resumed.txt"
for f in sandboxpaths-mounts sandboxpaths-resumed; do
  grep -q '^/mnt/tuist-cache /dev/vdc .*noatime' "$evidence/$f.txt"
  [[ $(grep -c '^/home/user/' "$evidence/$f.txt") == 5 ]]
  grep -qx '/home/user/go user:user' "$evidence/$f.txt"
  grep -qx 'foreign 0' "$evidence/$f.txt"
done
sandbox_paths=$(guest sandboxpaths "$build
build \$user /home/user /usr/local/go /home/user/workspace/tuist off")
api POST /v1/sandboxes/sandboxpaths/delete >/dev/null
echo "sandbox paths: $sandbox_paths"

create '{"id":"runnerpaths","template":"default","vcpus":2,"memory_mb":4096,"workspace_gb":1,"from_disk_snapshot":"go-src","cache_image":"runner-master"}'
runner_paths=$(guest runnerpaths "$build
$mount_cache
mount_cache /home/runner 1000:1000
build 1000 /home/runner '$runner_goroot' '$runner_src' off")
api POST /v1/sandboxes/runnerpaths/delete >/dev/null
echo "runner paths: $runner_paths"

sudo test ! -d "$work/data/jail/firecracker/runnerpaths"
master_sha_after=$(sudo sha256sum "$master" | cut -d' ' -f1)
last() { tail -n1 <<< "$1"; }
chown_of() { awk '$1 == "chown_ms" { print $2 }' <<< "$1"; }
boot_of() { jq -r .boot_ms "$evidence/create-$1.json"; }
jq -n \
  --arg job "$(tr '\n' ' ' < "$evidence/job.txt")" --arg master "$(basename "$master")" \
  --arg cold "$(last "$cold")" \
  --arg cold_boot "$(boot_of cold)" --arg sandbox_boot "$(boot_of sandboxpaths)" \
  --arg sandbox "$(last "$sandbox_paths")" \
  --arg runner "$(last "$runner_paths")" --arg runner_chown "$(chown_of "$runner_paths")" \
  --arg guest "$(cat "$evidence/guest.txt")" \
  --argjson master_intact "$([[ $master_sha_before == "$master_sha_after" ]] && echo true || echo false)" \
  '{note: "exit ms compiles CGO_ENABLED", runner_image_job: $job, master: $master, guest: $guest,
    sandbox_without_cache: {build: $cold, boot_ms: $cold_boot},
    sandbox_paths_with_master: {build: $sandbox, boot_ms_including_guest_mount: $sandbox_boot},
    runner_paths_with_master: {build: $runner, chown_ms: $runner_chown},
    master_intact: $master_intact}' | tee "$evidence/runner-master.json"
jq -e '.master_intact' "$evidence/runner-master.json" >/dev/null
echo 'DONE: a runner-cache master filled by the runner image, attached unmodified to sandboxes.'
echo 'NOT COVERED: the agent HTTP API, server authorization, object storage, production node filesystems.'
