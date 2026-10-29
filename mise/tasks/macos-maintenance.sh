#!/usr/bin/env bash
#MISE description="Plan or request serialized xcresult Mac host OS maintenance"
set -euo pipefail
context=${1:?usage: macos-maintenance CONTEXT NAMESPACE FLEET VERSION [--apply]}
namespace=${2:?namespace required}
fleet=${3:?fleet required}
target=${4:?explicit macOS target required}
mode=${5:---plan}
[[ "$target" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || { echo 'Use an explicit macOS point release' >&2; exit 1; }
[[ "$mode" == --plan || "$mode" == --apply ]] || { echo 'Expected --plan or --apply' >&2; exit 1; }
[[ "$context" == tuist-k8s-* ]] || { echo 'Use the named Pomerium kubectl context' >&2; exit 1; }
machines=$(kubectl --context "$context" -n "$namespace" get scalewayapplesiliconmachines -o json)
selected=$(jq --arg fleet "$fleet" '[.items[] | select(.spec.fleetName == $fleet and .metadata.deletionTimestamp == null)]' <<<"$machines")
[[ $(jq length <<<"$selected") -ge 2 ]] || { echo 'Maintenance requires at least two fleet hosts and a Ready processor peer' >&2; exit 1; }
if jq -e 'any(.[]; .status.osUpdate != null and .status.osUpdate.phase != "Succeeded")' <<<"$selected" >/dev/null; then
  echo 'A maintenance request is active or failed; inspect status before submitting another wave.' >&2
  exit 1
fi
jq -r --arg target "$target" '.[] | "\(.metadata.name) → macOS \($target)"' <<<"$selected"
if [[ "$mode" != --apply ]]; then
  echo 'Plan only. Add --apply after approving the target and completing canary acceptance.'
  exit 0
fi
# The controller owns sequencing and recovery. The client sends intent only;
# an expired elevation or closed terminal cannot interrupt a submitted host.
while IFS= read -r machine; do
  kubectl --context "$context" -n "$namespace" annotate scalewayapplesiliconmachine "$machine" "tuist.dev/os-update=$target"
done < <(jq -r '.[].metadata.name' <<<"$selected")
echo "Submitted. Inspect .status.osUpdate on the selected machines; failures hold the fleet lock."
