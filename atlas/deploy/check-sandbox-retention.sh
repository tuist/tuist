#!/usr/bin/env bash
# Read-only pre-upgrade check for managed retirement of legacy namespaces.
# Run after release recovery, since rollback can remove the keep annotation.
set -euo pipefail
values=${1:?Usage: check-sandbox-retention.sh VALUES RELEASE RELEASE_NAMESPACE}
release=${2:?Release name required}
release_namespace=${3:?Release namespace required}
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

enabled=$(yq --unwrapScalar '.agentSandboxes.enabled' "$values")
case "$enabled" in
  true|false) ;;
  *) echo 'agentSandboxes.enabled must be a boolean for the retirement check.' >&2; exit 1 ;;
esac

# Use Helm's stored manifest as the deletion/ownership source, not the desired
# namespace name or live ownership annotations, which may have been stripped.
installed=$(helm list --all --namespace "$release_namespace" --output json |
  jq --raw-output --arg release "$release" 'if type == "array" then any(.[]; .name == $release) else error("Invalid release listing") end')
if [ "$installed" = false ]; then
  exit 0
fi
previous=$(helm get manifest "$release" --namespace "$release_namespace" |
  yq eval-all -o=json '.' | jq --slurp '[.[] | select(.kind == "Namespace") | .metadata.name]')
# A failed latest revision can differ from the last deployed one Helm upgrades
# against. Protect the union rather than guessing which revision Helm selects.
deployed_revision=$(helm history "$release" --namespace "$release_namespace" --output json |
  jq --raw-output 'map(select(.status == "deployed")) | max_by(.revision | tonumber) | .revision // empty')
if [ -n "$deployed_revision" ]; then
  deployed=$(helm get manifest "$release" --namespace "$release_namespace" --revision "$deployed_revision" |
    yq eval-all -o=json '.' | jq --slurp '[.[] | select(.kind == "Namespace") | .metadata.name]')
  previous=$(jq --compact-output --argjson deployed "$deployed" '. + $deployed | unique' <<< "$previous")
fi
target=$(helm template "$release" "$root/infra/helm/atlas" --namespace "$release_namespace" --values "$values" |
  yq eval-all -o=json '.' | jq --slurp '[.[] | select(.kind == "Namespace") | .metadata.name]')

while IFS= read -r legacy_namespace; do
  if jq --exit-status --arg namespace "$legacy_namespace" 'index($namespace) != null' <<< "$target" > /dev/null; then
    continue
  fi

  namespace=$(kubectl --request-timeout=10s get namespace "$legacy_namespace" --ignore-not-found --output json)
  if [ -z "$namespace" ]; then
    continue
  fi
  jq --exit-status 'type == "object" and (.metadata | type == "object")' <<< "$namespace" > /dev/null
  retained=$(jq --raw-output '.metadata.annotations["helm.sh/resource-policy"] == "keep"' <<< "$namespace")
  if [ "$retained" != true ]; then
    echo 'Refusing legacy namespace retirement or rename: deploy retention first and verify it after any rollback.' >&2
    exit 1
  fi
done < <(jq --raw-output '.[]' <<< "$previous")
