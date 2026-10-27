#!/usr/bin/env bash
# Real KVM lifecycle on a disposable GitHub-hosted VM. This intentionally
# cannot target an existing sandboxd or cluster. The fake Amp process tests
# our bootstrap helper across real memory snapshots; it does not claim an
# authenticated Amp handshake or server admission coverage.
# Guest snippets expand variables inside the VM, not in this host shell.
# shellcheck disable=SC2016
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "${RUNNER_ENVIRONMENT:-}" == github-hosted ]] || {
  echo 'Run this only on a disposable GitHub-hosted Linux runner.' >&2
  exit 1
}
[[ $(uname -sm) == 'Linux x86_64' ]]
test -c /dev/kvm
work=$(mktemp -d "${RUNNER_TEMP:?}/sandbox-orbs.XXXXXX")
evidence="$RUNNER_TEMP/sandbox-orbs-evidence"
mkdir -p "$evidence" "$work/data"
daemon="sandbox-orbs-${GITHUB_RUN_ID:?}-${GITHUB_RUN_ATTEMPT:-1}"
loop=''
cleanup() {
  local rc=$?
  trap - EXIT
  docker logs "$daemon" > "$evidence/sandboxd.log" 2>&1 || true
  docker rm -f "$daemon" >/dev/null 2>&1 || true
  if mountpoint -q "$work/data"; then sudo umount "$work/data" || rc=1; fi
  if [[ -n "$loop" ]] && ! mountpoint -q "$work/data"; then sudo losetup -d "$loop" || rc=1; fi
  # Removing the backing file is safe only after its filesystem is unmounted.
  if ! mountpoint -q "$work/data"; then rm -rf "$work"; fi
  exit "$rc"
}
trap cleanup EXIT
exec > >(tee "$evidence/lifecycle.log") 2>&1

# A private XFS loop filesystem exercises production's strict FICLONE path.
truncate -s 24G "$work/data.xfs"
loop=$(sudo losetup --find --show "$work/data.xfs")
sudo mkfs.xfs -q -m reflink=1 "$loop"
sudo mount "$loop" "$work/data"
docker run --rm -v "$work/data:/host" -e TEMPLATE_TAG=validation sandbox-orbs-template:validation

start_daemon() {
  docker run -d --name "$daemon" --privileged --cgroupns=host \
    -v "$work/data:/data/sandboxes" \
    -p 127.0.0.1:9471:9471 \
    -e ADMIN_ADDR=:9471 -e TEMPLATE_TAG=validation \
    -e BOOT_TIMEOUT=120s -e TEMPLATE_BOOT_TIMEOUT=180s \
    -e SHUTDOWN_TIMEOUT=60s \
    sandbox-orbs-daemon:validation >/dev/null
  for _ in {1..60}; do
    if curl --silent --fail http://127.0.0.1:9471/healthz >/dev/null; then return; fi
    [[ $(docker inspect -f '{{.State.Running}}' "$daemon") == true ]] || break
    sleep 1
  done
  docker logs "$daemon"
  return 1
}
api() {
  local method=$1 path=$2
  shift 2
  curl --silent --show-error --fail-with-body --max-time 300 \
    -H 'content-type: application/json' -X "$method" "http://127.0.0.1:9471$path" "$@"
}
guest() {
  local response
  response=$(api POST /v1/sandboxes/amp-validation/exec \
    --data "$(jq -nc --arg script "$1" '{cmd:["/bin/bash","-euc",$script],timeout_ms:60000}')")
  if ! jq -e '.exit_code == 0' <<< "$response" >/dev/null; then
    jq . <<< "$response"
    return 1
  fi
  jq -r '.stdout' <<< "$response"
}
assert_no_vm() {
  # A paused sandbox must have no live VMM; saved memory is now disk state.
  docker exec "$daemon" sh -ec '! pidof firecracker'
}

start_daemon
api POST /v1/sandboxes --data '{"id":"amp-validation","template":"default","vcpus":2,"memory_mb":4096,"workspace_gb":1}' | tee "$evidence/create.json"
guest 'uname -m; /usr/local/bin/amp --version; /usr/local/bin/amp orb bootstrap --help; runuser -u user -- sudo -n id -u; curl --fail --silent --show-error --max-time 20 --output /dev/null https://ampcode.com'
guest 'runuser -u user -- bash -euc '\''source <(printf "value=process-substitution-ok\n"); test "$value" = process-substitution-ok; test "$(cat <(printf read-ok))" = read-ok; printf write-ok > /dev/stdout'\'''

# Retain the real Amp executable, then install a credential-free stand-in in
# this disposable guest only. The production bootstrap helper is unchanged.
guest 'mv /usr/local/bin/amp /usr/local/bin/amp-real
cat > /usr/local/bin/amp <<"AMP"
#!/usr/bin/env bash
set -euo pipefail
[[ $(id -un) == user && $HOME == /home/user ]]
[[ -z ${AMP_ORB_PROVIDER_TOKEN:-} && -z ${TUIST_TOKEN:-} ]]
echo boot >> /home/user/bootstrap-starts
exec sleep 3600
AMP
chmod +x /usr/local/bin/amp
ORB_TOKEN=validation-first AMP_URL=https://amp.example.invalid AMP_ORB_PROVIDER_TOKEN=must-not-cross TUIST_TOKEN=must-not-cross /usr/local/bin/sbx-orb-bootstrap
cp /run/tuist-amp/process /home/user/first-bootstrap
runuser -u user -- bash -c "echo retained > /home/user/workspace/marker"
cat > /home/user/counter.sh <<"COUNTER"
#!/usr/bin/env bash
count=0
while true; do count=$((count+1)); echo "$count" > /workspace/amp/counter; sleep 1; done
COUNTER
nohup bash /home/user/counter.sh </dev/null >/dev/null 2>&1 &
echo $! > /home/user/counter.pid
awk "{print \$22}" /proc/$!/stat > /home/user/counter.start
sleep 2
[[ $(cat /workspace/amp/counter) -ge 1 ]]
ORB_TOKEN=validation-first AMP_URL=https://amp.example.invalid /usr/local/bin/sbx-orb-bootstrap
cmp /run/tuist-amp/process /home/user/first-bootstrap
[[ $(wc -l < /home/user/bootstrap-starts) == 1 ]]
echo "guest setup and duplicate bootstrap passed"'

api POST /v1/sandboxes/amp-validation/pause | tee "$evidence/pause.json"
api GET /v1/sandboxes/amp-validation | jq -e '.state == "paused"' >/dev/null
assert_no_vm
sleep 3
api POST /v1/sandboxes/amp-validation/resume | tee "$evidence/resume.json"
guest '[[ $(cat /home/user/workspace/marker) == retained ]]
cmp /run/tuist-amp/process /home/user/first-bootstrap
read -r pid _ < /run/tuist-amp/process
kill -0 "$pid"
counter=$(cat /home/user/counter.pid)
[[ $(awk "{print \$22}" /proc/$counter/stat) == $(cat /home/user/counter.start) ]]
before=$(cat /workspace/amp/counter); sleep 2; [[ $(cat /workspace/amp/counter) -gt $before ]]
ORB_TOKEN=validation-refreshed AMP_URL=https://amp.example.invalid /usr/local/bin/sbx-orb-bootstrap
read -r current _ < /run/tuist-amp/process
read -r previous _ < /home/user/first-bootstrap
[[ $current != "$previous" ]]
kill -0 "$current"; kill -0 "$counter"
[[ $(wc -l < /home/user/bootstrap-starts) == 2 ]]
cp /run/tuist-amp/process /home/user/refreshed-bootstrap
echo "snapshot preserved memory, files and background process; credential refresh passed"'

# Clean daemon restart while active must snapshot the guest before exiting.
docker stop --time 75 "$daemon" >/dev/null
docker logs "$daemon" > "$evidence/sandboxd-before-restart.log" 2>&1
docker rm "$daemon" >/dev/null
start_daemon
api GET /v1/sandboxes/amp-validation | jq -e '.state == "paused" and (.cold_boot != true)' >/dev/null
api POST /v1/sandboxes/amp-validation/resume | tee "$evidence/resume-after-restart.json"
guest 'cmp /run/tuist-amp/process /home/user/refreshed-bootstrap
read -r pid _ < /run/tuist-amp/process; kill -0 "$pid"
counter=$(cat /home/user/counter.pid)
[[ $(awk "{print \$22}" /proc/$counter/stat) == $(cat /home/user/counter.start) ]]
[[ $(cat /home/user/workspace/marker) == retained ]]
echo "clean daemon restart preserved guest processes and files"'

api POST /v1/sandboxes/amp-validation/delete >/dev/null
api POST /v1/sandboxes/amp-validation/delete >/dev/null
api GET /v1/sandboxes | jq -e '(.sandboxes // []) | length == 0' >/dev/null
assert_no_vm
sudo test ! -d "$work/data/jail/firecracker/amp-validation"
echo 'PASS: real Firecracker create, guest bootstrap, pause/resume, token refresh, clean daemon restart and repeatable deletion.'
echo 'NOT COVERED: authenticated Amp handshake, Tuist HTTP/auth/database mapping, fleet admission or Kubernetes rollout.'
