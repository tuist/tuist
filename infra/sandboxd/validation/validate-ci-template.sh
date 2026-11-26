#!/usr/bin/env bash
# Boots a sandbox template built from another OCI image through the shared
# template builder (infra/sandbox-image's GUEST_IMAGE): the published Linux
# runner image as template `ci`. Checks the guest contract (user and runner on
# UID 1000, builder on 2000, sudo), that the runner image's environment and
# toolchain reach the guest, a build step as `runner`, and a warm pause and
# resume. Runs on a disposable GitHub-hosted KVM runner
# (sandbox-orbs-validation.yml, ci_template input), or on a dedicated KVM host
# with SANDBOXD_VALIDATION_HOST=dedicated after building both images.
# Guest snippets expand variables inside the VM, not in this host shell.
# shellcheck disable=SC2016
set -euo pipefail
if [[ "${GITHUB_ACTIONS:-}" == true && "${RUNNER_ENVIRONMENT:-}" == github-hosted ]]; then
  base=${RUNNER_TEMP:?}
  daemon="ci-template-${GITHUB_RUN_ID:?}-${GITHUB_RUN_ATTEMPT:-1}"
elif [[ "${SANDBOXD_VALIDATION_HOST:-}" == dedicated ]]; then
  base=${VALIDATION_DIR:-/var/tmp}
  daemon="ci-template-$$"
else
  echo 'Run this only on a disposable GitHub-hosted runner or a dedicated KVM host (SANDBOXD_VALIDATION_HOST=dedicated).' >&2
  exit 1
fi
template_image=${TEMPLATE_IMAGE:-sandbox-ci-template:validation}
daemon_image=${DAEMON_IMAGE:-sandbox-orbs-daemon:validation}
[[ $(uname -sm) == 'Linux x86_64' ]]
test -c /dev/kvm
work=$(mktemp -d "$base/ci-template.XXXXXX")
evidence=${EVIDENCE_DIR:-$base/ci-template-evidence}
mkdir -p "$evidence" "$work/data"
id=ci-template
loop=''
cleanup() {
  local rc=$?
  trap - EXIT
  docker logs "$daemon" > "$evidence/sandboxd.log" 2>&1 || true
  docker rm -f "$daemon" >/dev/null 2>&1 || true
  if mountpoint -q "$work/data"; then sudo umount "$work/data" || rc=1; fi
  if [[ -n "$loop" ]] && ! mountpoint -q "$work/data"; then sudo losetup -d "$loop" || rc=1; fi
  if ! mountpoint -q "$work/data"; then rm -rf "$work"; fi
  exit "$rc"
}
trap cleanup EXIT
exec > >(tee "$evidence/ci-template.log") 2>&1

truncate -s 40G "$work/data.xfs"
loop=$(sudo losetup --find --show "$work/data.xfs")
sudo mkfs.xfs -q -m reflink=1 "$loop"
sudo mount "$loop" "$work/data"
started=$(date +%s)
docker run --rm -v "$work/data:/host" -e TEMPLATE_NAME=ci -e TEMPLATE_TAG=validation -e ROOTFS_SIZE=20G "$template_image"
echo "template installed in $(( $(date +%s) - started ))s"
sudo cat "$work/data/templates/ci/validation/metadata.json" | tee "$evidence/metadata.json"
jq -e '.name == "ci" and .runner_uid == 1000 and .runner_gid == 1000' "$evidence/metadata.json" >/dev/null
echo "rootfs allocated: $(sudo du -h "$work/data/templates/ci/validation/rootfs.ext4" | cut -f1)"

docker run -d --name "$daemon" --privileged --cgroupns=host --dns 1.1.1.1 --dns 8.8.8.8 \
  -v "$work/data:/data/sandboxes" -p 127.0.0.1:9471:9471 \
  -e ADMIN_ADDR=:9471 -e TEMPLATE_NAME=ci -e TEMPLATE_TAG=validation \
  -e BOOT_TIMEOUT=60s -e TEMPLATE_BOOT_TIMEOUT=300s \
  "$daemon_image" >/dev/null
for _ in {1..60}; do
  curl --silent --fail http://127.0.0.1:9471/healthz >/dev/null && break
  sleep 1
done
api() {
  local method=$1 path=$2
  shift 2
  curl --silent --show-error --fail-with-body --max-time 600 \
    -H 'content-type: application/json' -X "$method" "http://127.0.0.1:9471$path" "$@"
}
guest() {
  local response
  response=$(api POST "/v1/sandboxes/$id/exec" \
    --data "$(jq -nc --arg script "$1" '{cmd:["/bin/bash","-euc",$script],timeout_ms:300000}')")
  jq -e '.exit_code == 0' <<< "$response" >/dev/null || { jq . <<< "$response"; return 1; }
  jq -r '.stdout' <<< "$response"
}

echo '== create from the ci template (builds its 2x4096 shape snapshot first)'
started=$(date +%s)
api POST /v1/sandboxes --data "{\"id\":\"$id\",\"template\":\"ci\",\"vcpus\":2,\"memory_mb\":4096,\"workspace_gb\":2}" | tee "$evidence/create.json"
echo "first create (template boot, snapshot and restore) took $(( $(date +%s) - started ))s"

echo '== guest contract'
guest '[[ $(id -u user) == 1000 && $(id -u runner) == 1000 && $(id -g user) == 1000 ]]
[[ $(id -u builder) == 2000 ]]
runuser -u user -- sudo -n true
! runuser -u builder -- sudo -n true 2>/dev/null
[[ -d /home/user && -d /home/runner ]]
for b in /sbin/sbx-init /usr/local/bin/sbx-agent /usr/local/bin/sbx-worker /usr/local/bin/sbx-executor; do [[ -x $b ]]; done
echo "contract: user=$(id user)"'

echo '== the runner image reaches the guest'
guest 'runuser -l runner -c '\''set -eu
[ "$ImageOS" = ubuntu24 ]
[ -d "$ANDROID_HOME/platforms" ] && [ -d "$ANDROID_HOME/build-tools" ]
test -x /home/runner/actions-runner/run.sh
for t in git git-lfs docker gh kubectl helm cmake ninja gcc python3 jq zstd; do command -v $t >/dev/null || { echo missing $t; exit 1; }; done
echo "runner env: ImageOS=$ImageOS ANDROID_HOME=$ANDROID_HOME"
echo "android platforms: $(ls $ANDROID_HOME/platforms | tr \"\\n\" \" \")"'\'''

echo '== a CI step as runner: clone and build a C project'
guest 'mkdir -p /workspace/work && chown 1000:1000 /workspace/work
runuser -l runner -c '\''set -eu
cd /workspace/work
git clone --quiet --depth 1 https://github.com/madler/zlib.git
cd zlib && cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release >/dev/null
start=$(date +%s); ninja -C build >/dev/null; echo "zlib built in $(( $(date +%s) - start ))s"
./build/example >/dev/null && echo "zlib example passed"
stat -c "%U %u" /workspace/work/zlib/build/example'\'''

echo '== warm pause and resume'
guest 'nohup bash -c "n=0; while true; do n=\$((n+1)); echo \$n > /workspace/counter; sleep 1; done" </dev/null >/dev/null 2>&1 &
echo $! > /root/counter.pid; awk "{print \$22}" /proc/$!/stat > /root/counter.start; sleep 2'
api POST "/v1/sandboxes/$id/pause" --data '{"sync_disks":true}' | tee "$evidence/pause.json"
api POST "/v1/sandboxes/$id/resume" | tee "$evidence/resume.json"
guest 'pid=$(cat /root/counter.pid); [[ $(awk "{print \$22}" /proc/$pid/stat) == $(cat /root/counter.start) ]]
before=$(cat /workspace/counter); sleep 2; [[ $(cat /workspace/counter) -gt $before ]]
[[ -x /workspace/work/zlib/build/example ]]
echo "process and files survived the pause"'

echo '== a second create restores from the shape snapshot'
api POST /v1/sandboxes --data "{\"id\":\"$id-2\",\"template\":\"ci\",\"vcpus\":2,\"memory_mb\":4096,\"workspace_gb\":2}" | tee "$evidence/create-2.json"
docker logs "$daemon" 2>&1 | grep -E 'template (snapshot|ready|built)|shape' | cut -c1-300 | tee "$evidence/template-build.log" || true
api POST "/v1/sandboxes/$id-2/delete" >/dev/null
api POST "/v1/sandboxes/$id/delete" >/dev/null
echo 'PASS: the Linux runner image boots as sandbox template ci through the shared builder, with the guest contract, its environment and toolchain, a CI build step as runner, and a warm pause and resume.'
