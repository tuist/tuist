#!/usr/bin/env bash
#
# Reports the macOS hosts that do not run the tart-kubelet of the deployed
# CAPI operator yet.
#
# tart-kubelet has no release of its own: it is compiled into the operator
# image (infra/cluster-api-provider-tuist/Dockerfile), and the operator's drift
# loop pushes it to every host after the deploy starts the operator, stamping
# `status.tartKubeletBinarySHA` on each push. Nothing in the Helm upgrade waits
# for that, so a deploy calls this until it reports no host.
#
# The SHA to reach is what the operator logs as it starts
# (`loaded tart-kubelet binary`, cmd/manager/main.go). An operator Pod whose
# log no longer holds that line has been running long enough for its log to
# rotate, so this deploy did not start it and pushed no new binary: there is
# nothing to wait for.
#
# The hosts are the ones serving: a Ready ScalewayAppleSiliconMachine or
# RackAppleSiliconMachine (a host lent to another env is `Lent`, and its
# borrower pushes its runtime), or an Active RackHostLease (a host this env
# borrows), whose Node is Ready and schedulable.
#
# Usage: tart-kubelet-rollout-gate.sh <namespace>
#   Reads the cluster through kubectl's current context. Prints one line per
#   host still on another binary, `<kind>/<name> <node> <sha|none> <failure|->`
#   tab-separated, and exits 1 when there is one. Exits 0 when every serving
#   host runs the operator's binary or there is nothing to check (no operator,
#   or an operator this deploy did not start). Any other exit is an error.
set -euo pipefail

namespace="${1:?usage: tart-kubelet-rollout-gate.sh <namespace>}"
k() { kubectl --request-timeout=30s -n "$namespace" "$@"; }

pods="$(k get pods -l app.kubernetes.io/component=capi-scaleway-applesilicon -o json \
  | jq -r '.items[] | select(.metadata.deletionTimestamp == null and .status.phase == "Running") | .metadata.name')"
if [ -z "$pods" ]; then
  echo "No CAPI operator runs in $namespace; no macOS host to check." >&2
  exit 0
fi

shas=()
for pod in $pods; do
  # The line is among the first the manager writes; a bounded read keeps a
  # long-lived Pod's log out of the job.
  log="$(k logs "$pod" -c manager --limit-bytes=1048576)"
  sha="$(grep -F '"loaded tart-kubelet binary"' <<< "$log" | head -n1 | jq -r '.sha // empty' || true)"
  if [ -n "$sha" ]; then
    shas+=("$sha")
  fi
done
if [ "${#shas[@]}" -eq 0 ]; then
  echo "The CAPI operator in $namespace was not started by this deploy; no new tart-kubelet to wait for." >&2
  exit 0
fi
expected="$(printf '%s\n' "${shas[@]}" | sort -u)"
if [ "$(wc -l <<< "$expected")" -ne 1 ]; then
  # Old and new operator Pods are both running: the rollout is not over.
  printf 'operator\t-\tmixed\tits Pods run different tart-kubelet binaries\n'
  exit 1
fi
echo "The CAPI operator in $namespace pushes tart-kubelet $expected." >&2

# Files, not arguments: a cluster's Node list outgrows the argument limit.
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
k get scalewayapplesiliconmachines -o json > "$scratch/scaleway.json"
k get rackapplesiliconmachines -o json > "$scratch/rack.json"
k get rackhostleases -o json > "$scratch/leases.json"
kubectl --request-timeout=30s get nodes -o json > "$scratch/nodes.json"

pending="$(jq -rn \
  --arg expected "$expected" \
  --slurpfile scaleway "$scratch/scaleway.json" \
  --slurpfile rack "$scratch/rack.json" \
  --slurpfile leases "$scratch/leases.json" \
  --slurpfile nodes "$scratch/nodes.json" '
  [$nodes[0].items[]
    | select(.spec.unschedulable != true)
    | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))
    | .metadata.name] as $serving
  | [
      (($scaleway[0].items[], $rack[0].items[])
        | select(.status.phase == "Ready")
        | {host: "\(.kind)/\(.metadata.name)", node: .metadata.name, status}),
      ($leases[0].items[]
        | select(.status.state == "Active")
        | {host: "\(.kind)/\(.metadata.name)", node: (.status.node // ""), status})
    ][]
  | select(.node as $node | $serving | index($node))
  | select(.status.tartKubeletBinarySHA != $expected)
  | [.host, .node, (.status.tartKubeletBinarySHA // "none"), (.status.failureReason // "-")]
  | @tsv')"

if [ -n "$pending" ]; then
  printf '%s\n' "$pending"
  exit 1
fi
