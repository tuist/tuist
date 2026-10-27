#!/usr/bin/env bash
# Pull each desired Linux pool image before Helm changes any pool.
# Usage: linux-runner-image-prepare.sh <rendered-json-array>
# The render is the announcement: use exactly the images/fleets/runtime classes
# the impending deploy will install, including manual pins and explicit pools.
set -euo pipefail
render="${1:?rendered JSON array required}"
work="$(mktemp -d)"
cleanup() {
  local manifest
  for manifest in "$work"/daemonset-*.json; do
    [[ -f "$manifest" ]] || continue
    kubectl --request-timeout=30s delete -f "$manifest" --ignore-not-found --wait=false >&2 || true
  done
  rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

jq -c '[.[] | select(.kind == "RunnerPool" and .spec.os == "linux") | {
  namespace: .metadata.namespace, fleet: .spec.fleetSelector,
  image: .spec.image, runtime: (.spec.runtimeClass // "")
}] | unique[]' "$render" > "$work/targets"
[[ -s "$work/targets" ]] || exit 0
deadline=$((SECONDS + ${LINUX_IMAGE_PREPARE_TIMEOUT_SECONDS:-600}))

# Apply every image first so different fleets/images pull concurrently. A
# distinct name per target prevents readiness of an old rollout passing a new
# one. No dispatch command, service-account token, or host mounts are needed.
while IFS= read -r target; do
  namespace="$(jq -er '.namespace' <<< "$target")"
  fleet="$(jq -er '.fleet | select(length > 0)' <<< "$target")"
  if ! image="$(jq -er '.image | select(test("@sha256:[a-f0-9]{64}$"))' <<< "$target")"; then
    echo "::error::Linux image preparation requires a digest-pinned image: $target" >&2
    exit 1
  fi
  nodes="$(kubectl --request-timeout=30s get nodes -l "kubernetes.io/os=linux,kubernetes.io/arch=amd64,node.cluster.x-k8s.io/pool=$fleet" -o json)"
  if [[ "$(jq '.items | length' <<< "$nodes")" == 0 ]]; then
    echo "No Linux hosts in $fleet yet; first installation will pull $image normally."
    continue
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sum="$(printf '%s' "$target" | sha256sum)"
  else
    sum="$(printf '%s' "$target" | shasum -a 256)"
  fi
  name="tuist-linux-prepull-${sum:0:20}"
  jq -n --argjson target "$target" --arg name "$name" '{
    apiVersion: "apps/v1", kind: "DaemonSet",
    metadata: {name: $name, namespace: $target.namespace},
    spec: {
      selector: {matchLabels: {"tuist.dev/linux-image-prepull": $name}},
      template: {
        metadata: {labels: {"tuist.dev/linux-image-prepull": $name}},
        spec: ({
          automountServiceAccountToken: false,
          terminationGracePeriodSeconds: 0,
          nodeSelector: {
            "kubernetes.io/os": "linux", "kubernetes.io/arch": "amd64",
            "node.cluster.x-k8s.io/pool": $target.fleet
          },
          tolerations: [
            {key: "tuist.dev/runner-tier", operator: "Equal", value: "bare-metal", effect: "NoSchedule"},
            {key: "tuist.dev/reserved-for", operator: "Exists", effect: "NoSchedule"}
          ],
          securityContext: {runAsNonRoot: true, runAsUser: 1000, seccompProfile: {type: "RuntimeDefault"}},
          containers: [{
            name: "pull", image: $target.image, imagePullPolicy: "IfNotPresent",
            command: ["/bin/sleep", "infinity"],
            resources: {requests: {cpu: "1m", memory: "16Mi"}, limits: {memory: "64Mi"}},
            securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: ["ALL"]}}
          }]
        } + if $target.runtime == "" then {} else {runtimeClassName: $target.runtime} end)
      }
    }
  }' > "$work/daemonset-$name.json"
  kubectl --request-timeout=30s apply -f "$work/daemonset-$name.json"
  echo "Pre-pulling $image on $fleet (${namespace}/${name})."
done < "$work/targets"

while true; do
  pending=false
  for manifest in "$work"/daemonset-*.json; do
    [[ -f "$manifest" ]] || continue
    namespace="$(jq -r '.metadata.namespace' "$manifest")"
    name="$(jq -r '.metadata.name' "$manifest")"
    fleet="$(jq -r '.spec.template.spec.nodeSelector["node.cluster.x-k8s.io/pool"]' "$manifest")"
    kubectl --request-timeout=30s get nodes -l "kubernetes.io/os=linux,kubernetes.io/arch=amd64,node.cluster.x-k8s.io/pool=$fleet" -o json > "$work/nodes.json"
    kubectl --request-timeout=30s -n "$namespace" get pods -l "tuist.dev/linux-image-prepull=$name" -o json > "$work/pods.json"
    uid="$(kubectl --request-timeout=30s -n "$namespace" get daemonset "$name" -o jsonpath='{.metadata.uid}')"
    if ! jq -e --arg uid "$uid" --slurpfile manifest "$manifest" --slurpfile pods "$work/pods.json" \
      -f "$(dirname "$0")/linux-runner-image-ready.jq" "$work/nodes.json" >/dev/null; then
      pending=true
      echo "Waiting for $namespace/$name on Ready, schedulable hosts in $fleet."
    fi
  done
  if [[ "$pending" == false ]]; then
    echo 'Linux runner images are staged on every Ready, schedulable host.'
    exit 0
  fi
  if (( SECONDS >= deadline )); then
    echo '::error::Linux image preparation timed out; runner pools have not been switched.' >&2
    exit 1
  fi
  sleep 10
done
