#!/usr/bin/env bash
# Authenticated live Amp on one disposable hosted VM. Never target a cluster.
# shellcheck disable=SC2016
set -euo pipefail
[[ ${GITHUB_ACTIONS:-} == true && ${RUNNER_ENVIRONMENT:-} == github-hosted ]]
[[ $(uname -sm) == 'Linux x86_64' ]]
test -c /dev/kvm
: "${AMP_ORB_PROVIDER_TOKEN:?Live validation requires the dedicated provider token}"
root=$(git rev-parse --show-toplevel)
work=$(mktemp -d "${RUNNER_TEMP:?}/amp-live.XXXXXX")
chmod 700 "$work"
# Keep observer configuration out of Amp's reserved AMP_* environment namespace.
export TUIST_ORB_VALIDATION_DIR="$work"
export KUBECONFIG="$work/kubeconfig"
evidence="$RUNNER_TEMP/amp-live-evidence"
mkdir -p "$evidence" "$work/data"
daemon="amp-live-${GITHUB_RUN_ID:?}"
cluster="amp-live-${GITHUB_RUN_ID}"
sa_dir=/var/run/secrets/kubernetes.io/serviceaccount
loop='' provider_pid='' server_pid='' own_sa=false
# shellcheck disable=SC2329
cleanup() {
  local rc=$?
  trap - EXIT
  if [[ -n "$provider_pid" ]]; then kill "$provider_pid" 2>/dev/null || true; wait "$provider_pid" || true; fi
  if [[ -n "$server_pid" ]]; then kill "$server_pid" 2>/dev/null || true; wait "$server_pid" || true; fi
  # Only bounded infrastructure logs and selected metadata are artifacts. No
  # environment, kubeconfig, provider log, guest console or credential files.
  docker logs "$daemon" > "$evidence/sandboxd.log" 2>&1 || true
  for file in state.json spawns.jsonl; do [[ ! -f "$work/$file" ]] || cp "$work/$file" "$evidence/"; done
  docker rm -f "$daemon" >/dev/null 2>&1 || true
  kind delete cluster --name "$cluster" >/dev/null 2>&1 || true
  if [[ "$own_sa" == true ]]; then sudo rm -rf "$sa_dir"; fi
  if mountpoint -q "$work/data"; then sudo umount "$work/data" || rc=1; fi
  if [[ -n "$loop" ]] && ! mountpoint -q "$work/data"; then sudo losetup -d "$loop" || rc=1; fi
  if ! mountpoint -q "$work/data"; then rm -rf "$work"; fi
  exit "$rc"
}
trap cleanup EXIT
exec > >(tee "$evidence/lifecycle.log") 2>&1

# Genuine TokenReview against a throwaway kind API. The bound Pod supplies
# the node identity; sandboxd itself runs in a privileged Docker container.
test ! -e "$sa_dir"
kind create cluster --name "$cluster" --wait 120s
kubectl create namespace tuist-sandboxes
kubectl -n tuist-sandboxes create serviceaccount sandboxd
kubectl -n tuist-sandboxes run identity --image=registry.k8s.io/pause:3.10 \
  --overrides='{"spec":{"serviceAccountName":"sandboxd"}}'
kubectl -n tuist-sandboxes wait --for=condition=Ready pod/identity --timeout=120s
node=$(kubectl -n tuist-sandboxes get pod identity -o jsonpath='{.spec.nodeName}')
uid=$(kubectl -n tuist-sandboxes get pod identity -o jsonpath='{.metadata.uid}')
kubectl -n tuist-sandboxes create token sandboxd --audience=tuist-sandboxes --duration=2h \
  --bound-object-kind=Pod --bound-object-name=identity --bound-object-uid="$uid" > "$work/node-token"
kubectl -n default create serviceaccount verifier
kubectl create clusterrolebinding amp-live-tokenreview --clusterrole=system:auth-delegator --serviceaccount=default:verifier
sudo mkdir -p "$sa_dir"
own_sa=true
kubectl -n default create token verifier --duration=2h | sudo tee "$sa_dir/token" >/dev/null
kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d | sudo tee "$sa_dir/ca.crt" >/dev/null
api_server=$(kubectl config view -o jsonpath='{.clusters[0].cluster.server}')
export KUBERNETES_SERVICE_HOST=127.0.0.1
export KUBERNETES_SERVICE_PORT="${api_server##*:}"

truncate -s 24G "$work/data.xfs"
loop=$(sudo losetup --find --show "$work/data.xfs")
sudo mkfs.xfs -q -m reflink=1 "$loop"
sudo mount "$loop" "$work/data"
docker run --rm -v "$work/data:/host" -e TEMPLATE_TAG=validation sandbox-orbs-template:validation

export TUIST_URL=http://127.0.0.1:4187
export TUIST_SERVER_TEST_PORT=4187
export TUIST_SERVER_TEST_POSTGRES_DB=tuist_amp_orbs_live
export TUIST_SERVER_TEST_CLICKHOUSE_DB=tuist_amp_orbs_live
export TUIST_ORB_WORKSPACE_GB=1 ORB_IMAGE=default
[[ $(command -v mix) != */shims/* ]]
(cd "$root/server"; exec env -u AMP_ORB_PROVIDER_TOKEN \
  TUIST_SERVER_TEST_POSTGRES_DB=tuist_amp_orbs_live \
  TUIST_SERVER_TEST_CLICKHOUSE_DB=tuist_amp_orbs_live TUIST_SERVER_TEST_PORT=4187 \
  mix run --no-start --no-compile verification/amp_orbs.exs) > "$work/server.log" 2>&1 &
server_pid=$!
for _ in {1..120}; do
  [[ ! -f "$work/provider.env" ]] || break
  kill -0 "$server_pid" || { tail -50 "$work/server.log"; exit 1; }
  sleep 1
done
test -f "$work/provider.env"
# shellcheck disable=SC1091
source "$work/provider.env"

# Host networking otherwise inherits systemd-resolved's 127.0.0.53 stub.
# sandboxd passes its resolvers to guests, where that loopback is unreachable.
docker run -d --name "$daemon" --privileged --cgroupns=host --network=host --dns=1.1.1.1 --memory=6g \
  -v "$work/data:/data/sandboxes" -v "$work/node-token:/var/run/secrets/tuist/token:ro" \
  -e SERVER_URL="$TUIST_URL" -e NODE_NAME="$node" -e ADMIN_ADDR=127.0.0.1:9471 \
  -e TEMPLATE_TAG=validation -e DISK_BUDGET_GIB=22 -e BOOT_TIMEOUT=120s \
  -e TEMPLATE_BOOT_TIMEOUT=180s -e SHUTDOWN_TIMEOUT=60s \
  sandbox-orbs-daemon:validation >/dev/null
for _ in {1..120}; do
  if jq -e '.nodes | length == 1' "$work/state.json" >/dev/null 2>&1; then break; fi
  sleep 1
done
jq -e '.nodes | length == 1' "$work/state.json" >/dev/null
echo 'PASS: sandboxd authenticated through real Kubernetes TokenReview and connected to Tuist.'

# The controller uses the same pinned, checksum-verified Amp as the guest.
version=$(sed -n 's/^ARG AMP_VERSION=//p' "$root/infra/sandbox-image/Dockerfile")
curl --fail --silent --show-error "https://static.ampcode.com/cli/$version/amp-linux-x64" -o "$work/amp"
curl --fail --silent --show-error "https://static.ampcode.com/cli/$version/linux-x64-amp.sha256" -o "$work/amp.sha256"
printf '%s  %s\n' "$(cat "$work/amp.sha256")" "$work/amp" | sha256sum -c -
chmod +x "$work/amp"
start_provider() {
  "$work/amp" orb provider "$root/infra/amp-orbs/live-dispatch.sh" </dev/null >> "$work/provider.log" 2>&1 &
  provider_pid=$!
  sleep 3
  kill -0 "$provider_pid"
}
start_provider
echo 'READY: select the dedicated provider in Amp and send the first validation prompt.'
echo 'First prompt: Run `echo first-turn > /workspace/amp/from-amp-first` and report success. Then pause the Orb.'
printf '### Live Amp validation ready\nSelect the dedicated provider and send the first prompt. See the job log for phase changes.\n' >> "$GITHUB_STEP_SUMMARY"

deadline=$((SECONDS + 1800))
first_id='' restarted=false second_seen=false
while (( SECONDS < deadline )); do
  kill -0 "$server_pid"
  kill -0 "$provider_pid"
  state=$(cat "$work/state.json")
  count=$(jq '.sandboxes | length' <<< "$state")
  (( count <= 1 )) || { echo 'Use only one validation thread with this provider.'; exit 1; }
  if (( count == 1 )); then
    id=$(jq -r '.sandboxes[0].id' <<< "$state")
    orb=$(jq -r '.sandboxes[0].amp_orb_id' <<< "$state")
    if [[ -z "$first_id" ]]; then first_id=$id; fi
    [[ "$id" == "$first_id" ]]
    phase=$(jq -r '.sandboxes[0].state' <<< "$state")
    [[ "$phase" != error ]] || { echo 'Sandbox entered error state.'; exit 1; }
    if [[ "$phase" == paused ]]; then
      jq -e '.sandboxes[0].residency_work_id == null' <<< "$state" >/dev/null || { sleep 1; continue; }
      docker exec "$daemon" sh -ec '! pidof firecracker'
      if [[ "$restarted" == false ]]; then
        kill "$provider_pid"; wait "$provider_pid" || true
        start_provider
        restarted=true
        echo 'PASS: first pause released residency and VMM memory. Provider restarted; mapping retained.'
        echo 'READY: continue the SAME Amp thread with: Read /workspace/amp/from-amp-first, then run `echo second-turn > /workspace/amp/from-amp-second` and report success. Then pause the Orb.'
      elif [[ "$second_seen" == true ]]; then
        echo 'PASS: second turn paused successfully.'
        ORB_OPERATION=delete ORB_ID="$orb" "$root/infra/amp-orbs/dispatch.sh"
        ORB_OPERATION=delete ORB_ID="$orb" "$root/infra/amp-orbs/dispatch.sh"
        for _ in {1..10}; do
          if jq -e '.sandboxes | length == 0' "$work/state.json" >/dev/null; then break; fi
          sleep 1
        done
        jq -e '.sandboxes | length == 0' "$work/state.json" >/dev/null
        echo 'PASS: authenticated Amp turns, HTTP dispatch, durable mapping, pause/resume, provider restart, files, processes and idempotent deletion.'
        echo 'NOT COVERED: production build/configuration, multi-replica control plane, fleet-controller admission or Kubernetes deployment rollout.'
        exit 0
      fi
    elif [[ "$phase" == running && "$restarted" == true && "$second_seen" == false ]]; then
      # Read-only guest probe: no resume and no lifecycle bypass. Amp must
      # wake the guest through the real dispatch path first.
      body='{"cmd":["/bin/bash","-ec","test \"$(cat /workspace/amp/from-amp-first)\" = first-turn; test \"$(cat /workspace/amp/from-amp-second)\" = second-turn"],"timeout_ms":5000}'
      result=$(curl --silent --show-error --fail --max-time 10 -H 'content-type: application/json' \
        --data "$body" "http://127.0.0.1:9471/v1/sandboxes/$id/exec" || true)
      if jq -e '.exit_code == 0' <<< "$result" >/dev/null 2>&1; then
        jq -e --arg orb "$orb" '.sandboxes[0].residency_work_id == ("amp:" + $orb)' <<< "$state" >/dev/null
        [[ $(wc -l < "$work/spawns.jsonl") -ge 2 ]]
        second_seen=true
        echo 'PASS: Amp wrote both markers in the same sandbox; resumed background process and active residency verified.'
      fi
    fi
  fi
  sleep 1
done
echo 'Timed out waiting for two Amp turns and pauses. Provider stopped; isolated VM removed.'
exit 1
