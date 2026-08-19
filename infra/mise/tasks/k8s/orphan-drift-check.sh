#!/usr/bin/env bash
#MISE description="Report live Kubernetes objects that no chart on main renders and no controller owns."
#USAGE arg "<environment>" help="Environment to check (staging | canary | production)"

# Finds the class of orphan that every other signal misses: an object that is
# live in a cluster, is rendered by no chart on main, and has no
# ownerReferences. All three have to hold at once, and that conjunction is
# what makes the report small enough to read.
#
# Why each half exists:
#
#   * Not rendered by main. Helm only prunes what a release still tracks, so
#     an object created by a chart that never landed on main (a feature-branch
#     `helm upgrade`, a hand-applied manifest) is invisible to every later
#     `helm upgrade` -- nothing will ever prune it, and `helm list` shows a
#     healthy release. CRDs are worse: Helm does not prune them at all, so a
#     CRD outlives the chart that introduced it indefinitely.
#   * No ownerReferences. This is the filter that makes the report usable. The
#     clusters are full of objects no chart renders on purpose -- CNPG's Pods
#     and Services, the kura-controller's StatefulSets, every ReplicaSet --
#     and all of them carry an ownerReference to the thing that reconciles
#     them. An object with no owner is one nothing is watching: if it should
#     not exist, nothing will notice.
#
# Measured against the three orphans found by hand on 2026-08-18/19
# (tuist/tuist#12442, tuist/tuist#12467, the kuragateways CRD left by
# tuist/tuist#11644): all three had no ownerReferences, none was rendered by
# main, and none surfaced in a dashboard, an alert, or helm state. They were
# found because a person went looking.
#
# Report only. It deletes nothing and is not built to: two of those three
# needed a human decision about whether the data behind them mattered.
#
# Environment knobs:
#   KUBECTL_CONTEXT   kubectl context to read (default: current context)
#   MIN_AGE_HOURS     ignore objects younger than this (default 24)
#   JSON_OUT          also write the findings as JSON to this path
#   RELEASES_FILE     override infra/orphan-drift/releases.txt
#   ALLOWLIST_FILE    override infra/orphan-drift/allowlist.txt
#   RENDER_ONLY       render every release and exit; no cluster access needed

set -euo pipefail

ENVIRONMENT="${1:-}"
if [ -z "$ENVIRONMENT" ]; then
  echo "usage: orphan-drift-check.sh <staging|canary|production>" >&2
  echo "       RENDER_ONLY=1 orphan-drift-check.sh all   # validate charts, no cluster" >&2
  exit 2
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
RELEASES_FILE="${RELEASES_FILE:-$REPO_ROOT/infra/orphan-drift/releases.txt}"
ALLOWLIST_FILE="${ALLOWLIST_FILE:-$REPO_ROOT/infra/orphan-drift/allowlist.txt}"
MIN_AGE_HOURS="${MIN_AGE_HOURS:-24}"
JSON_OUT="${JSON_OUT:-}"

KUBECTL=(kubectl)
if [ -n "${KUBECTL_CONTEXT:-}" ]; then
  KUBECTL+=(--context "$KUBECTL_CONTEXT")
fi
KUBECTL+=(--request-timeout=60s)

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*" >&2; }

# Custom API groups we own end to end. Every resource the cluster reports in
# these groups is policed, so a CRD we add later is covered without editing
# this list -- which is the point, since an abandoned CRD is one of the three
# cases this check exists for.
OWNED_API_GROUPS=(kura.tuist.dev tuist.dev postgresql.cnpg.io)

# Built-in kinds worth policing, as `<group>:<resource>` (empty group = core).
# Deliberately narrow: these are the kinds that cost money or serve traffic
# when abandoned, and they are the kinds all three known orphans took.
# Widening this (to ConfigMaps, Secrets, ServiceAccounts, RBAC) buys a much
# larger report for objects that are inert when stranded.
BUILTIN_RESOURCES=(
  :namespaces
  :services
  apps:deployments
  apps:statefulsets
  apiextensions.k8s.io:customresourcedefinitions
)

# Image tags are resolved at deploy time from git tags and pushed images, and
# a few templates hard-fail without them. None of them affects which objects
# render -- only what those objects run -- so the check pins placeholders
# rather than reimplementing the deploy workflow's tag resolution.
PLACEHOLDER_SETS=(
  # Top-level image.tag is the single-component charts (slack,
  # noora-storybook, typesense, tuist-ops); the rest are the tuist chart's.
  --set image.tag=orphan-drift
  --set server.image.tag=orphan-drift
  --set codebaseSearch.image.tag=orphan-drift
  --set registry.image.tag=orphan-drift
  --set kuraController.image.tag=orphan-drift
  --set kuraRuntime.image.tag=orphan-drift
  --set xcresultProcessor.image.tag=orphan-drift
  --set macosFleet.image.tag=orphan-drift
  --set runnersController.image.tag=orphan-drift
  --set runnersFleet.runnerImageSemver=0.0.0
  --set runnersFleetLinux.shapeRunnerImage=ghcr.io/tuist/tuist-linux-runner:orphan-drift
)

# Renders one release exactly as the check compares it. Shared with
# RENDER_ONLY so the config validated on a pull request is the same config the
# scheduled run uses -- a chart that stops rendering does not fail the check
# loudly, it silently reports every object it owns as an orphan.
template_release() {
  local chart="$1" release="$2" namespace="$3" values="$4" out="$5"
  local chart_dir="$REPO_ROOT/$chart"
  local values_args=() values_file

  for values_file in $values; do
    values_args+=(-f "$chart_dir/$values_file")
  done

  # Subchart tarballs have to be present for `helm template` to resolve
  # dependency references; no-op for charts without `dependencies:`.
  if grep -q '^dependencies:' "$chart_dir/Chart.yaml"; then
    helm dependency update "$chart_dir" >/dev/null
  fi

  # --include-crds matters: the tuist and platform charts ship CRDs under
  # crds/, which the deploy applies separately (`kubectl apply -f crds/`).
  # Without it every chart CRD would be reported as an orphan.
  helm template "$release" "$chart_dir" \
    --namespace "$namespace" --include-crds \
    "${values_args[@]}" "${PLACEHOLDER_SETS[@]}" > "$out"
}

release_rows() {
  grep -v '^[[:space:]]*#' "$RELEASES_FILE" | awk 'NF'
}

# RENDER_ONLY validates the repository half without touching a cluster, which
# is all a pull request can check: every release still renders, so the
# comparison still has a left-hand side.
if [ -n "${RENDER_ONLY:-}" ]; then
  render_status=0
  while read -r environment chart release namespace values; do
    [ "$ENVIRONMENT" = "all" ] || [ "$environment" = "$ENVIRONMENT" ] || continue
    if template_release "$chart" "$release" "$namespace" "$values" /dev/null; then
      echo "ok    $environment $release ($chart)"
    else
      echo "FAIL  $environment $release ($chart)" >&2
      render_status=1
    fi
  done < <(release_rows)
  exit $render_status
fi

##
## 1. Resource scope: what kinds to police, and which of them are cluster-scoped.
##
## Read from the cluster's discovery API rather than `kubectl api-resources`,
## whose columns are positional and shift with the optional SHORTNAMES and
## CATEGORIES fields. Scope matters twice: it decides what to list, and it
## decides how a rendered object's namespace is normalised below.
##
log "Discovering policed resources"

resource_rows="$WORK_DIR/resources.tsv" # <resource.group> <group> <Kind> <namespaced>
: > "$resource_rows"

# Prints one row per listable, non-subresource in a group's preferred version.
discover_group() {
  local group="$1" group_version raw
  if [ -z "$group" ]; then
    group_version="v1"
    raw="$("${KUBECTL[@]}" get --raw /api/v1)" || return 1
  else
    group_version="$("${KUBECTL[@]}" get --raw "/apis/$group" 2>/dev/null |
      jq -r '.preferredVersion.version // empty')"
    [ -n "$group_version" ] || return 1
    raw="$("${KUBECTL[@]}" get --raw "/apis/$group/$group_version" 2>/dev/null)" || return 1
  fi
  printf '%s' "$raw" | jq -r --arg group "$group" '
    .resources[]
    # Subresources ("deployments/status") are not objects.
    | select(.name | test("/") | not)
    | select((.verbs // []) | index("list"))
    | [(.name + (if $group == "" then "" else "." + $group end)), $group, .kind, (.namespaced | tostring)]
    | @tsv'
}

for entry in "${BUILTIN_RESOURCES[@]}"; do
  group="${entry%%:*}"
  resource="${entry#*:}"
  [ -z "$group" ] || resource="$resource.$group"
  discover_group "$group" | awk -F'\t' -v want="$resource" '$1 == want' >> "$resource_rows"
done

for group in "${OWNED_API_GROUPS[@]}"; do
  if ! rows="$(discover_group "$group")" || [ -z "$rows" ]; then
    echo "note: API group $group is not served by this cluster" >&2
    continue
  fi
  printf '%s\n' "$rows" >> "$resource_rows"
done

if [ ! -s "$resource_rows" ]; then
  echo "ERROR: discovered no resources to police -- is the cluster reachable?" >&2
  exit 1
fi

sort -u "$resource_rows" -o "$resource_rows"

# group|Kind -> namespaced, consumed by the rendered-side namespace defaulting.
scope_json="$WORK_DIR/scope.json"
jq -R -s 'split("\n") | map(select(length > 0) | split("\t"))
  | map({ key: (.[1] + "|" + .[2]), value: (.[3] == "true") }) | from_entries' \
  < "$resource_rows" > "$scope_json"

echo "Policing: $(cut -f1 "$resource_rows" | tr '\n' ' ')" >&2

##
## 2. Rendered side: every object identity main's charts produce for this env.
##
log "Rendering charts for $ENVIRONMENT"

rendered_ids="$WORK_DIR/rendered.txt"
: > "$rendered_ids"
rendered_releases=0

while read -r environment chart release namespace values; do
  [ "$environment" = "$ENVIRONMENT" ] || continue
  rendered_releases=$((rendered_releases + 1))

  render="$WORK_DIR/render-$release.yaml"
  template_release "$chart" "$release" "$namespace" "$values" "$render"

  # An object that omits metadata.namespace lands in the release namespace,
  # so that is what a namespaced kind defaults to here. Cluster-scoped kinds
  # are forced to empty on both sides so the two halves compare.
  yq -o=json -I=0 'select(.kind != null and .metadata.name != null)
      | [.apiVersion, .kind, (.metadata.namespace // ""), .metadata.name]' "$render" |
    jq -r --arg release_ns "$namespace" --slurpfile scope "$scope_json" '
      . as [$api_version, $kind, $object_ns, $name]
      | select($api_version != null and $kind != null and $name != null)
      | (if ($api_version | test("/")) then ($api_version | split("/")[0]) else "" end) as $group
      | ($group + "|" + $kind) as $gk
      | select($scope[0] | has($gk))
      | (if $scope[0][$gk] then (if $object_ns == "" then $release_ns else $object_ns end) else "" end) as $ns
      | [$group, $kind, $ns, $name] | @tsv' >> "$rendered_ids"
done < <(release_rows)

if [ "$rendered_releases" -eq 0 ]; then
  echo "ERROR: no releases in $RELEASES_FILE for environment '$ENVIRONMENT'" >&2
  exit 1
fi

sort -u "$rendered_ids" -o "$rendered_ids"
echo "Rendered $rendered_releases release(s), $(wc -l < "$rendered_ids" | tr -d ' ') policed object identities" >&2

##
## 3. Live side: unowned objects of the policed kinds.
##
log "Listing live objects"

live_json="$WORK_DIR/live.json"
: > "$live_json"

# pipefail (set at the top) is load-bearing here: a failed `kubectl get` in
# this pipeline aborts the run rather than feeding jq nothing and reporting a
# healthy-looking short list. Under-reporting is the failure this check cannot
# afford -- it is indistinguishable from a clean cluster.
while IFS=$'\t' read -r resource _group _kind _namespaced; do
  "${KUBECTL[@]}" get "$resource" --all-namespaces -o json |
    jq -c --argjson min_age_hours "$MIN_AGE_HOURS" --arg environment "$ENVIRONMENT" '
      .items[]
      # An owned object is somebody else'"'"'s problem by construction: whatever
      # holds the ownerReference is reconciling it, and garbage collection
      # removes it when the owner goes. This is the filter that keeps CNPG
      # pods, kura StatefulSets and every ReplicaSet out of the report.
      | select((.metadata.ownerReferences // []) | length == 0)
      # Already terminating -- finalizers can hold this for a while.
      | select(.metadata.deletionTimestamp == null)
      | select(.metadata.creationTimestamp != null)
      | ((now - (.metadata.creationTimestamp | fromdateiso8601)) / 3600) as $age_hours
      # A deploy in flight while the check runs would otherwise report the
      # objects it is still creating.
      | select($age_hours >= $min_age_hours)
      | {
          group: (if (.apiVersion | test("/")) then (.apiVersion | split("/")[0]) else "" end),
          kind: .kind,
          namespace: (.metadata.namespace // ""),
          name: .metadata.name,
          ageDays: (($age_hours / 24) | floor),
          createdAt: .metadata.creationTimestamp,
          environment: $environment,
        }' >> "$live_json"
done < "$resource_rows"

echo "Found $(wc -l < "$live_json" | tr -d ' ') live unowned object(s) older than ${MIN_AGE_HOURS}h" >&2

##
## 4. Subtract the rendered set, then the allowlist.
##
log "Comparing"

findings_json="$WORK_DIR/findings.json"
jq -s \
  --rawfile rendered "$rendered_ids" \
  --rawfile allowlist "$ALLOWLIST_FILE" '
  def key: [.group, .kind, .namespace, .name] | join("\t");

  # Allowlist columns are literal text with `*` as the only wildcard, so a
  # rule reads like the object it excuses rather than like a regex.
  def glob_to_regex:
    "^" + (gsub("(?<c>[.^$|()\\[\\]{}+?\\\\])"; "\\\(.c)") | gsub("\\*"; ".*")) + "$";

  ($rendered | split("\n") | map(select(length > 0)) | INDEX(.)) as $rendered_set
  | ($allowlist | split("\n")
      | map(sub("[[:space:]]*#.*$"; "") | split("[[:space:]]+"; "") | map(select(length > 0)))
      | map(select(length == 3))
      | map({
          group_kind: (.[0] | glob_to_regex),
          namespace: (.[1] | (if . == "-" then "" else . end) | glob_to_regex),
          name: (.[2] | glob_to_regex),
        })) as $allowlist_rules
  | map(. + { groupKind: ((if .group == "" then "core" else .group end) + "/" + .kind) })
  | map(select(key as $object_key | ($rendered_set | has($object_key)) | not))
  | map(select(. as $object
      | $allowlist_rules
      | any(. as $rule
            | ($object.groupKind | test($rule.group_kind))
              and ($object.namespace | test($rule.namespace))
              and ($object.name | test($rule.name)))
      | not))
  | sort_by(-.ageDays)' < "$live_json" > "$findings_json"

if [ -n "$JSON_OUT" ]; then
  cp "$findings_json" "$JSON_OUT"
fi

count="$(jq 'length' < "$findings_json")"

if [ "$count" -eq 0 ]; then
  echo "orphan-drift-check: $ENVIRONMENT: no candidate orphans"
  exit 0
fi

echo "orphan-drift-check: $ENVIRONMENT: $count candidate orphan(s)"
echo
jq -r '(["KIND","NAMESPACE","NAME","AGE"] | @tsv),
       (.[] | [.groupKind, (if .namespace == "" then "-" else .namespace end), .name, "\(.ageDays)d"] | @tsv)' \
  < "$findings_json" | column -t -s $'\t'
