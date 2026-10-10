#!/usr/bin/env bash
#MISE description="Check that no release a deploy waits on has a pod bound to a rack node"
set -euo pipefail

# Deploys wait on the tuist, k8s-monitoring and platform releases, and Helm's
# wait holds a DaemonSet until every pod it wants is Ready. A rack is dark for
# days at a time, so a DaemonSet in one of those releases that wants a pod on a
# rack node, or a Deployment pinned to one, fails every deploy while it is.
# What runs on rack nodes ships in releases nothing waits on: rack-nodes and
# rack-cache-gateways. See "Deploys and the rack's health" in
# infra/rack-nodes/AGENTS.md.
#
# Each env's charts are rendered and their pod specs scheduled, by nodeSelector,
# required node affinity and tolerations, against the nodes a rack has: one per
# role in rackLinuxFleet.roles, a rack Linux node with no role taint, and a
# rack's Mac mini. The unwaited releases must land on them, which keeps the
# model honest. Every rendered Service name has to fit the 63 characters the
# API server allows, since most charts build names from the release name.

ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
HELM="$ROOT/infra/helm"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

render() {
  local out="$1"
  shift
  helm template "$@" | yq -o json -I0 'select(.kind != null)' | jq -s . > "$WORK/$out.json"
}

for chart in k8s-monitoring platform rack-cache-gateways; do
  helm dependency update "$HELM/$chart" >/dev/null
done

for env in staging production; do
  case "$env" in
    production) platform_overlay="values-tuist.yaml" ;;
    *) platform_overlay="values-tuist-$env.yaml" ;;
  esac
  tuist_values=(-f "$HELM/tuist/values-managed-common.yaml" -f "$HELM/tuist/values-managed-$env.yaml")
  platform_values=(-f "$HELM/platform/values-hetzner.yaml" -f "$HELM/platform/$platform_overlay")

  render "waited-tuist-$env" tuist "$HELM/tuist" --namespace tuist "${tuist_values[@]}" -f "$HELM/tuist/values-ci.yaml"
  render "waited-k8s-monitoring-$env" k8s-monitoring "$HELM/k8s-monitoring" --namespace observability -f "$HELM/k8s-monitoring/values-$env.yaml"
  render "waited-platform-$env" platform "$HELM/platform" --namespace platform "${platform_values[@]}"
  render "unwaited-rack-nodes-$env" tuist-rack-nodes "$HELM/rack-nodes" --namespace tuist -f "$HELM/tuist/values.yaml" "${tuist_values[@]}"
  render "unwaited-rack-cache-gateways-$env" rack-cache-gateways "$HELM/rack-cache-gateways" --namespace platform -f "$HELM/platform/values.yaml" "${platform_values[@]}"
  yq -o json -I0 '{"roles": (.rackLinuxFleet.roles // {}), "fleet": (.rackFleet.name // "tuist-tuist-rack-fleet")}' "$HELM/tuist/values-managed-$env.yaml" > "$WORK/rack-$env.json"
done

for file in "$WORK"/waited-*.json "$WORK"/unwaited-*.json; do
  jq -c --arg name "$(basename "$file" .json)" '{($name): .}' "$file"
done | jq -s add > "$WORK/renders.json"

jq -n -r \
  --slurpfile racks <(cat "$WORK"/rack-*.json) \
  --slurpfile renders "$WORK/renders.json" '
  def base: {"kubernetes.io/os": "linux", "node.cluster.x-k8s.io/instance-type": "rack", "cilium.io/no-schedule": "true"};

  def nodes:
    [{name: "rack Linux node without a role", labels: base, taints: []}]
    + [$racks[] | .roles | to_entries[]
        | {name: "rack \(.key) node", labels: (base + (.value.nodeLabels // {})), taints: (.value.nodeTaints // [])}]
    + [$racks[] | {name: "rack Mac mini",
        labels: {"kubernetes.io/os": "darwin", "tuist.dev/runtime": "tart", "tuist.dev/fleet": .fleet},
        taints: [{key: "tuist.dev/macos", value: "true", effect: "NoSchedule"}]}]
    | unique_by(.name + (.labels | tostring) + (.taints | tostring));

  def matches($labels):
    $labels[.key] as $value
    | if .operator == "In" then $value != null and (.values | index($value)) != null
      elif .operator == "NotIn" then $value == null or (.values | index($value)) == null
      elif .operator == "Exists" then $value != null
      elif .operator == "DoesNotExist" then $value == null
      else false end;

  def selects($labels):
    ((.nodeSelector // {}) | to_entries | all(.value == $labels[.key]))
    and ((.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms // null) as $terms
         | $terms == null or ($terms | any((.matchExpressions // []) | length > 0 and all(matches($labels)))));

  def tolerates($taints):
    (.tolerations // []) as $tolerations
    | $taints | all(. as $taint
        | $tolerations | any(
            ((.key // "") == "" and .operator == "Exists" or .key == $taint.key and ((.operator // "Equal") == "Exists" or .value == $taint.value))
            and ((.effect // "") == "" or .effect == $taint.effect)));

  def schedulable($node): selects($node.labels) and tolerates($node.taints);

  def pinned_to_rack:
    [(.nodeSelector // {} | to_entries[] | [.key, .value]),
     (.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms // [] | .[].matchExpressions // [] | .[]
        | select(.operator == "In") | .key as $key | .values[] | [$key, .])]
    | any(.[0] | startswith("tuist.dev/rack-"))
      or any(.[0] == "node.cluster.x-k8s.io/instance-type" and .[1] == "rack")
      or any(.[0] == "node.cluster.x-k8s.io/pool" and (.[1] | startswith("rack-")));

  nodes as $nodes
  | [$renders[0] | to_entries[] | .key as $release | .value[]
      | select(.kind == "DaemonSet" or .kind == "Deployment" or .kind == "StatefulSet")
      | {release: $release, workload: "\(.kind)/\(.metadata.name)", kind, spec: .spec.template.spec}
      | .landsOn = [.spec as $spec | $nodes[] | select(. as $node | $spec | schedulable($node)) | .name]
      | .pinned = (.spec | pinned_to_rack)] as $workloads
  | ([$workloads[] | select(.release | startswith("waited-"))
      | select(.kind == "DaemonSet" and (.landsOn | length) > 0 or .kind != "DaemonSet" and .pinned)
      | "\(.release | ltrimstr("waited-")): \(.workload) runs on rack nodes (\(.landsOn | join(", ")))"])
    + ([$workloads[] | select(.release | startswith("unwaited-")) | select(.kind == "DaemonSet" and (.landsOn | length) == 0)
      | "\(.release | ltrimstr("unwaited-")): \(.workload) runs on no rack node, so the rack node model is wrong"])
    + ([$renders[0] | to_entries[] | .key as $release | .value[]
      | select(.kind == "Service" and (.metadata.name | length) > 63)
      | "\($release | sub("^(un)?waited-"; "")): Service/\(.metadata.name) has \(.metadata.name | length) characters, and the API server refuses a Service name longer than 63"])
  | .[]
' > "$WORK/failures.txt"

if [ -s "$WORK/failures.txt" ]; then
  echo "These releases would fail a deploy, or hold one up while the rack is dark:" >&2
  sed 's/^/  /' "$WORK/failures.txt" >&2
  exit 1
fi
echo "No release a deploy waits on runs a pod on a rack node, and every Service name fits."
