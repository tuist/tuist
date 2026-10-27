#!/usr/bin/env bash
# Start background preparation and check readiness once, like the macOS gate.
# Usage: linux-runner-image-prepare.sh <rendered-json-array> <release> <namespace>
# stdout is a Helm values object holding unprepared pools on their current image;
# diagnostics go to stderr. The caller warns and uses no holds on API errors.
set -euo pipefail
render="${1:?rendered JSON array required}"
release="${2:?Helm release required}"
release_namespace="${3:?Helm namespace required}"
script_dir="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
now="${NOW:-$(date -u +%s)}"
timeout="${LINUX_IMAGE_STAGING_TIMEOUT_SECONDS:-3600}"
hash() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi
}
owner="$(printf '%s/%s' "$release_namespace" "$release" | hash)"
owner="${owner:0:20}"
selector="tuist.dev/linux-image-staging-owner=$owner"
kubectl --request-timeout=30s get runnerpools.tuist.dev --all-namespaces -o json > "$work/current.json"
jq -c --slurpfile current "$work/current.json" '[.[]
  | select(.kind == "RunnerPool" and .spec.os == "linux")
  | . as $desired
  | ($current[0].items | map(select(.metadata.namespace == $desired.metadata.namespace and .metadata.name == $desired.metadata.name)) | first) as $old
  | select($old != null and $old.spec.image != .spec.image)
  | {namespace: .metadata.namespace, fleet: .spec.fleetSelector, image: .spec.image,
     # Managed Kata shares containerd overlayfs with native pods. Avoid its
     # 2560 MiB VM overhead; retain unknown handlers and their snapshotters.
     runtime: (if .spec.runtimeClass == "kata-qemu" then "" else (.spec.runtimeClass // "") end),
     pool: .metadata.name, current: $old.spec.image}]
  | group_by([.namespace,.fleet,.image,.runtime])[]
  | {target: (.[0] | {namespace,fleet,image,runtime}), pools: map({pool,current})}' "$render" > "$work/targets"
echo '{}' > "$work/holds.json"
echo '[]' > "$work/keep.json"

while IFS= read -r group; do
  target="$(jq -c .target <<< "$group")"
  namespace="$(jq -er '.namespace' <<< "$target")"
  fleet="$(jq -er '.fleet | select(length > 0)' <<< "$target")"
  image="$(jq -er '.image | select(test("@sha256:[a-f0-9]{64}$"))' <<< "$target")"
  kubectl --request-timeout=30s get nodes -l "kubernetes.io/os=linux,kubernetes.io/arch=amd64,node.cluster.x-k8s.io/pool=$fleet" -o json > "$work/nodes.json"
  # Like macOS, no Ready/schedulable serving hosts means there is no hold.
  if ! jq -e 'any(.items[]; .metadata.deletionTimestamp == null and .spec.unschedulable != true and any(.status.conditions[]?; .type == "Ready" and .status == "True"))' "$work/nodes.json" >/dev/null; then
    echo "Linux $fleet: no Ready, schedulable hosts; moving to $image." >&2
    continue
  fi
  sum="$(printf '%s/%s' "$owner" "$target" | hash)"
  name="tuist-linux-prepull-${sum:0:20}"
  jq -n --argjson target "$target" --arg name "$name" --arg owner "$owner" \
    -f "$script_dir/linux-runner-image-daemonset.jq" > "$work/daemonset.json"
  # apply preserves creationTimestamp: later deployments must not restart the
  # one-hour staging allowance for the same target.
  kubectl --request-timeout=30s apply -f "$work/daemonset.json" >&2
  jq --arg key "$namespace/$name" '. + [$key]' "$work/keep.json" > "$work/next.json"
  mv "$work/next.json" "$work/keep.json"
  kubectl --request-timeout=30s -n "$namespace" get daemonset "$name" -o json > "$work/live.json"
  uid="$(jq -er .metadata.uid "$work/live.json")"
  announced_at="$(jq -r '.metadata.creationTimestamp | fromdateiso8601' "$work/live.json")"
  if (( now - announced_at >= timeout )); then
    echo "Linux $fleet: staged for at least ${timeout}s; moving without waiting for hosts." >&2
    continue
  fi
  kubectl --request-timeout=30s -n "$namespace" get pods -l "tuist.dev/linux-image-prepull=$name" -o json > "$work/pods.json"
  if jq -e --arg uid "$uid" --slurpfile manifest "$work/daemonset.json" --slurpfile pods "$work/pods.json" \
    -f "$script_dir/linux-runner-image-ready.jq" "$work/nodes.json" >/dev/null; then
    echo "Linux $fleet: every Ready, schedulable host holds $image; moving." >&2
    continue
  fi
  echo "Linux $fleet: preparing $image in the background; keeping existing pool images for this deployment." >&2
  jq --argjson pools "$(jq .pools <<< "$group")" '. + ($pools | map({key:.pool,value:.current}) | from_entries)' "$work/holds.json" > "$work/next.json"
  mv "$work/next.json" "$work/holds.json"
done < "$work/targets"

# Only this release owns these helpers. Keep pending pulls across deployments;
# remove targets once pools have actually moved or a deployment supersedes
# them. Retain their timestamps/proof if Helm later fails or rolls back.
# A cleanup failure must not discard the readiness decision.
if kubectl --request-timeout=30s get daemonsets --all-namespaces -l "$selector" -o json > "$work/daemonsets.json"; then
  jq -r --arg owner "$owner" --slurpfile keep "$work/keep.json" '.items[]
    | select(.metadata.labels["tuist.dev/linux-image-staging-owner"] == $owner)
    | (.metadata.namespace + "/" + .metadata.name) as $key
    | select($keep[0] | index($key) | not)
    | [.metadata.namespace,.metadata.name] | @tsv' "$work/daemonsets.json" |
    while IFS=$'\t' read -r namespace name; do
      kubectl --request-timeout=30s -n "$namespace" delete daemonset "$name" --ignore-not-found --wait=false >&2 ||
        echo "::warning::Could not remove Linux staging helper $namespace/$name." >&2
    done
else
  echo '::warning::Could not list obsolete Linux staging helpers for cleanup.' >&2
fi
jq '{runnersFleetLinux:{imageHolds:.}}' "$work/holds.json"
