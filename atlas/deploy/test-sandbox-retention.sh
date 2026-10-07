#!/usr/bin/env bash
# Test the managed pre-upgrade guard with fake Helm state and kubectl, not a cluster.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
printf 'agentSandboxes:\n  enabled: false\n  namespace: atlas-agents\n' > "$work/retired.yaml"
printf 'agentSandboxes:\n  enabled: true\n  namespace: atlas-agents\n' > "$work/retained.yaml"
printf 'agentSandboxes:\n  enabled: true\n  namespace: renamed-agents\n' > "$work/renamed.yaml"
printf 'agentSandboxes:\n  enabled: false\n  namespace: renamed-agents\n' > "$work/renamed-retired.yaml"
export REAL_HELM
REAL_HELM=$(command -v helm)
# Expand fixture variables in the generated commands, not this shell.
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash
case "$1" in
  list)
    if [ "${FAKE_HELM_FAILURE:-false}" = true ]; then exit 1; fi
    if [ "${FAKE_RELEASE_EXISTS:-true}" = true ]; then printf '\''[{"name":"atlas"}]'\''; else printf '\''[]'\''; fi ;;
  history)
    if [ "${FAKE_HELM_FAILURE:-false}" = true ]; then exit 1; fi
    printf '\''[{"revision":1,"status":"deployed"},{"revision":2,"status":"failed"}]'\'' ;;
  get)
    if [ "${FAKE_HELM_FAILURE:-false}" = true ]; then exit 1; fi
    if [ "${FAKE_LATEST_HAS_NAMESPACE:-true}" = false ] && [[ " $* " != *" --revision 1 "* ]]; then exit 0; fi
    printf "apiVersion: v1\nkind: Namespace\nmetadata:\n  name: atlas-agents\n" ;;
  template) exec "$REAL_HELM" "$@" ;;
  *) exit 81 ;;
esac
' > "$work/helm"
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash
if [ "$*" != "--request-timeout=10s get namespace atlas-agents --ignore-not-found --output json" ]; then
  echo "Unexpected namespace lookup" >&2; exit 81
fi
if [ "${FAKE_KUBECTL_FAILURE:-false}" = true ]; then exit 1; fi
printf "%%s" "${FAKE_NAMESPACE:-}"
' > "$work/kubectl"
chmod +x "$work/helm" "$work/kubectl"
export PATH="$work:$PATH"

export FAKE_NAMESPACE='{"metadata":{"annotations":{"meta.helm.sh/release-name":"atlas","meta.helm.sh/release-namespace":"atlas-production"}}}'
for values in retired renamed renamed-retired; do
  if bash "$here/check-sandbox-retention.sh" "$work/$values.yaml" atlas atlas-production 2> "$work/error"; then
    echo 'Guard allowed namespace deletion or rename without retention' >&2
    exit 1
  fi
  grep -q 'Refusing legacy namespace retirement' "$work/error"
done

# A failed latest revision without the namespace cannot hide a deployed one.
export FAKE_LATEST_HAS_NAMESPACE=false
if bash "$here/check-sandbox-retention.sh" "$work/retired.yaml" atlas atlas-production 2> "$work/error"; then
  echo 'Guard ignored the namespace in the last deployed revision' >&2
  exit 1
fi
grep -q 'Refusing legacy namespace retirement' "$work/error"
export FAKE_LATEST_HAS_NAMESPACE=true

# Enabling retention without renaming remains safe after an old deployment/rollback.
bash "$here/check-sandbox-retention.sh" "$work/retained.yaml" atlas atlas-production
export FAKE_NAMESPACE='{"metadata":{"annotations":{"helm.sh/resource-policy":"keep"}}}'
for values in retired renamed renamed-retired; do
  bash "$here/check-sandbox-retention.sh" "$work/$values.yaml" atlas atlas-production
done

# Stored manifest ownership is authoritative even if live annotations changed.
for namespace in '{"metadata":{}}' '{"metadata":{"annotations":{"meta.helm.sh/release-name":"other"}}}'; do
  export FAKE_NAMESPACE="$namespace"
  if bash "$here/check-sandbox-retention.sh" "$work/retired.yaml" atlas atlas-production 2>/dev/null; then
    echo 'Guard ignored a stored namespace after its ownership annotations changed' >&2
    exit 1
  fi
done

# Missing/invalid enablement is rejected, not silently treated as a fresh install.
for content in '{}' 'agentSandboxes: {}' 'agentSandboxes: {enabled: no}' 'agentSandboxes: {enabled: 0}'; do
  printf '%s\n' "$content" > "$work/invalid.yaml"
  if bash "$here/check-sandbox-retention.sh" "$work/invalid.yaml" atlas atlas-production 2> "$work/error"; then
    echo 'Guard allowed invalid retirement configuration' >&2
    exit 1
  fi
  grep -q 'must be a boolean' "$work/error"
done

export FAKE_NAMESPACE=''
bash "$here/check-sandbox-retention.sh" "$work/retired.yaml" atlas atlas-production
export FAKE_RELEASE_EXISTS=false
bash "$here/check-sandbox-retention.sh" "$work/renamed.yaml" atlas atlas-production
export FAKE_RELEASE_EXISTS=true FAKE_KUBECTL_FAILURE=true
if bash "$here/check-sandbox-retention.sh" "$work/retired.yaml" atlas atlas-production; then
  echo 'Guard allowed retirement after a failed namespace lookup' >&2; exit 1
fi
export FAKE_KUBECTL_FAILURE=false FAKE_NAMESPACE='not-json'
if bash "$here/check-sandbox-retention.sh" "$work/retired.yaml" atlas atlas-production 2>/dev/null; then
  echo 'Guard allowed retirement after an invalid lookup response' >&2; exit 1
fi
export FAKE_HELM_FAILURE=true
if bash "$here/check-sandbox-retention.sh" "$work/retired.yaml" atlas atlas-production; then
  echo 'Guard allowed retirement after a failed release lookup' >&2; exit 1
fi

echo 'Managed sandbox retention guard passed, including renames, rollback, and lookup failures.'
