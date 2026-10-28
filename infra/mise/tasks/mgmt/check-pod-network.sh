#!/usr/bin/env bash
#MISE description="Check DNS and bidirectional pod HTTP traffic between every management control-plane node"
set -euo pipefail

namespace=mgmt-network-check
run="network-$(date +%s)-$$"
image=busybox:1.37.0
fail() { echo "error: $*" >&2; exit 1; }
cleanup() {
  kubectl -n "$namespace" delete jobs,pods -l "mgmt-network-check=$run" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM

nodes="$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o json | jq -r '.items[].metadata.name' | sort)"
[[ "$(wc -w <<<"$nodes" | tr -d ' ')" -ge 2 ]] || fail "pod networking needs at least two control-plane nodes"
kubectl apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: $namespace
  labels:
    pod-security.kubernetes.io/enforce: restricted
EOF

pod_spec() {
  jq -n --arg node "$1" --arg image "$image" '{
    nodeName: $node, restartPolicy: "Never", automountServiceAccountToken: false,
    tolerations: [{operator: "Exists"}],
    securityContext: {runAsNonRoot: true, runAsUser: 65534, runAsGroup: 65534, seccompProfile: {type: "RuntimeDefault"}},
    containers: [{name: "check", image: $image,
      securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: ["ALL"]}}
    }]
  }'
}

while read -r node; do
  pod_spec "$node" | jq --arg name "$run-$node" --arg ns "$namespace" --arg run "$run" '{
    apiVersion: "v1", kind: "Pod", metadata: {name: $name, namespace: $ns, labels: {"mgmt-network-check": $run}},
    spec: (. + {activeDeadlineSeconds: 600, volumes: [{name: "www", emptyDir: {}}]} |
      .containers[0] += {
        command: ["sh", "-ec", "printf %s \"$NODE_NAME\" > /www/index.html; exec httpd -f -p 8080 -h /www"],
        env: [{name: "NODE_NAME", valueFrom: {fieldRef: {fieldPath: "spec.nodeName"}}}],
        volumeMounts: [{name: "www", mountPath: "/www"}],
        readinessProbe: {tcpSocket: {port: 8080}, periodSeconds: 2}
      })
  }' | kubectl apply -f - >/dev/null
done <<<"$nodes"

if ! kubectl -n "$namespace" wait --for=condition=Ready pod -l "mgmt-network-check=$run" --timeout=180s; then
  kubectl -n "$namespace" get pods -l "mgmt-network-check=$run" -o wide >&2
  fail "network probe servers did not start; inspect pod scheduling, image pulls and CNI"
fi
peers="$(kubectl -n "$namespace" get pods -l "mgmt-network-check=$run" -o json | jq -r '.items[] | .spec.nodeName + "=" + .status.podIP' | tr '\n' ' ')"
while read -r node; do
  pod_spec "$node" | jq --arg name "$run-$node" --arg ns "$namespace" --arg run "$run" --arg peers "$peers" '{
    apiVersion: "batch/v1", kind: "Job", metadata: {name: $name, namespace: $ns, labels: {"mgmt-network-check": $run}},
    spec: {backoffLimit: 0, activeDeadlineSeconds: 90,
      template: {metadata: {labels: {"mgmt-network-check": $run}}, spec: (
        . | .containers[0] += {
          env: [{name: "PEERS", value: $peers}],
          command: ["sh", "-ec", "nslookup kubernetes.default.svc.cluster.local; for peer in $PEERS; do node=${peer%=*}; ip=${peer#*=}; echo Checking $node at $ip; actual=$(wget -T 5 -qO- http://$ip:8080); test \"$actual\" = \"$node\"; done"]
        })}}
  }' | kubectl apply -f - >/dev/null
done <<<"$nodes"

deadline=$((SECONDS + 150))
while true; do
  jobs="$(kubectl -n "$namespace" get jobs -l "mgmt-network-check=$run" -o json)"
  if jq -e 'any(.items[]; any(.status.conditions[]?; .type == "Failed" and .status == "True"))' <<<"$jobs" >/dev/null || (( SECONDS >= deadline )); then
    kubectl -n "$namespace" get pods -l "mgmt-network-check=$run" -o wide >&2 || true
    while read -r node; do
      echo "==> Network probe on $node" >&2
      kubectl -n "$namespace" logs "job/$run-$node" --pod-running-timeout=5s >&2 || true
    done <<<"$nodes"
    fail "pod network gate failed (DNS or pod HTTP); check Flannel endpoints, routes and firewall before continuing"
  fi
  if jq -e --argjson count "$(wc -w <<<"$nodes")" '.items | length == $count and all(.[]; .status.succeeded == 1)' <<<"$jobs" >/dev/null; then
    echo "==> DNS and pod HTTP passed in every direction across: $(tr '\n' ' ' <<<"$nodes")"
    break
  fi
  sleep 3
done
