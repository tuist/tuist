#!/usr/bin/env bash
#MISE description="Check default KVM availability, rollback and host preparation"
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
chart="$root/infra/helm/tuist"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
for env in staging canary production; do
  render() {
    helm template tuist "$chart" -f "$chart/values-managed-common.yaml" -f "$chart/values-managed-$env.yaml" -f "$chart/values-ci.yaml" "$@" |
      yq -o=json -I=0 'select(.kind != null)' | jq -s .
  }
  render > "$work/on.json"
  render --set runnersFleetLinux.nestedVirtualization.defaultEnabled=false > "$work/off.json"
  jq -e '[.[]|select(.kind == "RunnerPool" and .spec.os == "linux")] | length > 0 and all(.[]; .spec.nestedVirtualization == true and .spec.runtimeClass == "kata-qemu")' "$work/on.json" >/dev/null
  jq -e 'all(.[]|select(.kind == "RunnerPool" and .spec.os == "linux"); .spec.nestedVirtualization != true)' "$work/off.json" >/dev/null
  jq -en --slurpfile on "$work/on.json" --slurpfile off "$work/off.json" '
    [$on[0][]|select(.kind == "RunnerPool" and .spec.os == "linux")] as $on |
    [$off[0][]|select(.kind == "RunnerPool" and .spec.os == "linux")] as $off |
    all($on[]; . as $pool | any($off[]; .metadata.name == $pool.metadata.name and .metadata.annotations["tuist.dev/runtime-class-revision"] != $pool.metadata.annotations["tuist.dev/runtime-class-revision"]))' >/dev/null
  if render --set runnersFleetLinux.nestedVirtualization.enabled=false > /dev/null 2> "$work/error"; then
    echo 'KVM default accepted without device plugin' >&2; exit 1
  fi
  echo "$env: every Linux pool has KVM; rollback changes the idle rollout revision."
done
yq -e '.runnersFleetLinux.nestedVirtualization.defaultEnabled == false and .runnersFleetLinux.nestedVirtualization.enabled == false' "$chart/values.yaml" >/dev/null
bash "$root/.github/scripts/runner-kvm-prepare.test.sh"
