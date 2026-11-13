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
  # Without NRI, both the global default and explicit pool/shape opt-ins must
  # reject the pod-level-resources/device-plugin combination that panics kubelet.
  for setting in \
    'runnersFleetLinux.exclusiveCPUs.defaultEnabled=true' \
    'runnersFleetLinux.pools[0].name=test,runnersFleetLinux.pools[0].dispatchLabel=test,runnersFleetLinux.pools[0].runtimeClass=kata-qemu,runnersFleetLinux.pools[0].exclusiveCPUs=true' \
    'runnersFleetLinux.shapes[0].exclusiveCPUs=true,runnersFleetLinux.shapes[0].vcpus=2,runnersFleetLinux.shapes[0].memoryGb=8'; do
    if render --set runnersFleetLinux.nestedVirtualization.nri.enabled=false --set "$setting" > /dev/null 2> "$work/error"; then
      echo "Unsafe exclusive CPUs with nested KVM accepted: $env $setting" >&2; exit 1
    fi
    grep -q 'exclusiveCPUs cannot be combined with nestedVirtualization' "$work/error"
  done
  render --set runnersFleetLinux.nestedVirtualization.defaultEnabled=false \
    --set runnersFleetLinux.exclusiveCPUs.defaultEnabled=true > "$work/exclusive.json"
  jq -e '[.[]|select(.kind == "RunnerPool" and .spec.os == "linux" and (.spec.podCPUMilli % 2000 == 0))] |
    length > 0 and all(.[]; .spec.exclusiveCPUs == true and .spec.nestedVirtualization != true)' "$work/exclusive.json" >/dev/null
  # With the NRI plugin, exclusive-CPU pools keep KVM without the device plugin.
  render --set runnersFleetLinux.nestedVirtualization.nri.enabled=true \
    --set runnersFleetLinux.exclusiveCPUs.defaultEnabled=true > "$work/nri.json"
  jq -e '[.[]|select(.kind == "RunnerPool" and .spec.os == "linux" and (.spec.podCPUMilli % 2000 == 0))] |
    length > 0 and all(.[]; .spec.exclusiveCPUs == true and .spec.nestedVirtualization == true)' "$work/nri.json" >/dev/null
  jq -e '[.[]|select(.kind == "DaemonSet" and .metadata.labels["app.kubernetes.io/component"] == "kvm-nri-plugin")] | length == 1' "$work/nri.json" >/dev/null
  # An env's own render has the NRI DaemonSet exactly when it enables NRI, and
  # exclusive CPUs only alongside it.
  if yq -e '.runnersFleetLinux.nestedVirtualization.nri.enabled == true' "$chart/values-managed-$env.yaml" >/dev/null 2>&1; then
    jq -e '[.[]|select(.kind == "DaemonSet" and .metadata.labels["app.kubernetes.io/component"] == "kvm-nri-plugin")] | length == 1' "$work/on.json" >/dev/null
  else
    jq -e 'all(.[]; .kind != "DaemonSet" or .metadata.labels["app.kubernetes.io/component"] != "kvm-nri-plugin")' "$work/on.json" >/dev/null
    jq -e 'all(.[]|select(.kind == "RunnerPool" and .spec.os == "linux"); .spec.exclusiveCPUs != true)' "$work/on.json" >/dev/null
  fi
  echo "$env: every Linux pool has KVM; rollback changes the idle rollout revision."
done
yq -e '.runnersFleetLinux.nestedVirtualization.defaultEnabled == false and .runnersFleetLinux.nestedVirtualization.enabled == false' "$chart/values.yaml" >/dev/null
bash "$root/.github/scripts/runner-kvm-prepare.test.sh"
