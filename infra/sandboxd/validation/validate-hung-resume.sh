#!/usr/bin/env bash
# A real Firecracker guest whose memory image was taken while its agent hung
# must still resume: sandboxd cold boots its disks in the same resume instead
# of restoring the hung image on every attempt. Runs on a disposable
# GitHub-hosted KVM runner (sandbox-orbs-validation.yml, hung_resume input), or
# on a dedicated KVM host that opts in with SANDBOXD_VALIDATION_HOST=dedicated
# after building both images with the tags below.
# Guest snippets expand variables inside the VM, not in this host shell.
# shellcheck disable=SC2016
set -euo pipefail
if [[ "${GITHUB_ACTIONS:-}" == true && "${RUNNER_ENVIRONMENT:-}" == github-hosted ]]; then
  base=${RUNNER_TEMP:?}
  daemon="hung-resume-${GITHUB_RUN_ID:?}-${GITHUB_RUN_ATTEMPT:-1}"
elif [[ "${SANDBOXD_VALIDATION_HOST:-}" == dedicated ]]; then
  # Off /tmp, which is often a RAM-backed tmpfs too small for the loop file.
  base=${VALIDATION_DIR:-/var/tmp}
  daemon="hung-resume-$$"
else
  echo 'Run this only on a disposable GitHub-hosted runner or a dedicated KVM host (SANDBOXD_VALIDATION_HOST=dedicated).' >&2
  exit 1
fi
template_image=${TEMPLATE_IMAGE:-sandbox-orbs-template:validation}
daemon_image=${DAEMON_IMAGE:-sandbox-orbs-daemon:validation}
[[ $(uname -sm) == 'Linux x86_64' ]]
test -c /dev/kvm
work=$(mktemp -d "$base/hung-resume.XXXXXX")
evidence=${EVIDENCE_DIR:-$base/hung-resume-evidence}
mkdir -p "$evidence" "$work/data"
id=hung-resume
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
exec > >(tee "$evidence/hung-resume.log") 2>&1

truncate -s 24G "$work/data.xfs"
loop=$(sudo losetup --find --show "$work/data.xfs")
sudo mkfs.xfs -q -m reflink=1 "$loop"
sudo mount "$loop" "$work/data"
docker run --rm -v "$work/data:/host" -e TEMPLATE_TAG=validation "$template_image"

# BOOT_TIMEOUT bounds each wait for the guest agent after a restore.
docker run -d --name "$daemon" --privileged --cgroupns=host --dns 1.1.1.1 --dns 8.8.8.8 \
  -v "$work/data:/data/sandboxes" -p 127.0.0.1:9471:9471 \
  -e ADMIN_ADDR=:9471 -e TEMPLATE_TAG=validation \
  -e BOOT_TIMEOUT=30s -e TEMPLATE_BOOT_TIMEOUT=180s \
  -e DIFF_SNAPSHOTS="${DIFF_SNAPSHOTS:-false}" \
  "$daemon_image" >/dev/null
for _ in {1..60}; do
  curl --silent --fail http://127.0.0.1:9471/healthz >/dev/null && break
  sleep 1
done
api() {
  local method=$1 path=$2
  shift 2
  curl --silent --show-error --fail-with-body --max-time 300 \
    -H 'content-type: application/json' -X "$method" "http://127.0.0.1:9471$path" "$@"
}
guest() {
  local response
  response=$(api POST "/v1/sandboxes/$id/exec" \
    --data "$(jq -nc --arg script "$1" '{cmd:["/bin/bash","-euc",$script],timeout_ms:60000}')")
  jq -e '.exit_code == 0' <<< "$response" >/dev/null || { jq . <<< "$response"; return 1; }
  jq -r '.stdout' <<< "$response"
}
state() { api GET "/v1/sandboxes/$id" | jq -c '{state, cold_boot: (.cold_boot // false), error}'; }
vmms() { docker exec "$daemon" sh -c 'pidof firecracker | wc -w'; }
start_counter() {
  guest 'nohup bash -c "n=0; while true; do n=\$((n+1)); echo \$n > /workspace/counter; sleep 1; done" </dev/null >/dev/null 2>&1 &
echo $! > /root/counter.pid; awk "{print \$22}" /proc/$!/stat > /root/counter.start; sleep 2'
}
counter_alive() {
  guest 'pid=$(cat /root/counter.pid); [[ -e /proc/$pid && $(awk "{print \$22}" /proc/$pid/stat) == $(cat /root/counter.start) ]] && echo alive || echo gone'
}

api POST /v1/sandboxes --data "{\"id\":\"$id\",\"template\":\"default\",\"vcpus\":2,\"memory_mb\":4096,\"workspace_gb\":1}" | tee "$evidence/create.json"
guest 'echo kept-across-the-hang > /workspace/marker; sync'
start_counter

echo '== control: a healthy guest resumes warm with its processes'
api POST "/v1/sandboxes/$id/pause" --data '{"sync_disks":true}' | tee "$evidence/control-pause.json"
api POST "/v1/sandboxes/$id/resume" | tee "$evidence/control-resume.json"
[[ $(counter_alive) == alive ]] || { echo 'FAIL: a healthy warm resume lost its process'; exit 1; }
echo 'control passed: warm resume kept the background process'

echo '== freeze the guest agent, then pause: the image holds a hung guest'
guest 'agent=$(pidof sbx-agent); setsid bash -c "sleep 2; kill -STOP $agent" </dev/null >/dev/null 2>&1 & echo "freezing sbx-agent pid $agent"'
sleep 5
# The pause's guest sync times out on the frozen agent, as production's did.
api POST "/v1/sandboxes/$id/pause" --data '{"sync_disks":true}' | tee "$evidence/hung-pause.json"
docker logs "$daemon" 2>&1 | grep 'guest sync before pause failed' | cut -c1-300 ||
  { echo 'FAIL: the guest agent still answered the pause'; exit 1; }
echo "after pause: $(state), firecracker processes: $(vmms)"

echo '== resume the hung image'
for attempt in 1 2; do
  started=$(date +%s)
  if api POST "/v1/sandboxes/$id/resume" > "$evidence/hung-resume-$attempt.json" 2>&1; then
    echo "resume $attempt succeeded after $(( $(date +%s) - started ))s: $(cat "$evidence/hung-resume-$attempt.json")"
    break
  fi
  echo "resume $attempt FAILED after $(( $(date +%s) - started ))s: $(cat "$evidence/hung-resume-$attempt.json")"
  echo "state: $(state)"
  if [[ $attempt == 2 ]]; then
    docker logs "$daemon" 2>&1 | grep -E 'agent not ready|spawn failed|cold booting' | cut -c1-300 || true
    echo 'FAIL: the hung image never resumes'; exit 1
  fi
done
echo "after resume: $(state), firecracker processes: $(vmms)"
docker logs "$daemon" 2>&1 | grep -E 'guest sync before pause failed|restoring the sandbox.s memory failed|cold booting on its own disks|sandbox (paused|resumed)' | cut -c1-300
[[ $(guest 'cat /workspace/marker') == kept-across-the-hang ]] || { echo 'FAIL: the file written before the hang is gone'; exit 1; }
echo 'the file written before the hang is still there'
[[ $(counter_alive) == gone ]] || { echo 'FAIL: the process survived, so the hung image was restored'; exit 1; }
echo 'the background process is gone: the guest cold booted'
[[ $(vmms) == 1 ]] || { echo 'FAIL: expected exactly one firecracker process'; exit 1; }

echo '== the next pause writes a fresh image that resumes warm'
start_counter
api POST "/v1/sandboxes/$id/pause" --data '{"sync_disks":true}' | tee "$evidence/after-pause.json"
api POST "/v1/sandboxes/$id/resume" | tee "$evidence/after-resume.json"
[[ $(counter_alive) == alive ]] || { echo 'FAIL: the fresh image did not resume warm'; exit 1; }
echo 'the fresh image resumed warm with its process'

api POST "/v1/sandboxes/$id/delete" >/dev/null
api POST "/v1/sandboxes/$id/delete" >/dev/null
[[ $(vmms) == 0 ]]
echo 'PASS: a real hung guest image cold boots on its disks in one resume, keeping files; healthy and fresh images still resume warm.'
