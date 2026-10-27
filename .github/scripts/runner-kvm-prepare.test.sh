#!/usr/bin/env bash
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export KVM_TEST_WORK="$work"
mkdir "$work/bin"
cat > "$work/bin/kubectl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >> "$KVM_TEST_WORK/calls"
if [[ "$*" == *'get nodes'* ]]; then
  cat "$KVM_TEST_WORK/nodes.json"
elif [[ "$*" == *'apply -f'* ]]; then
  cp "${@: -1}" "$KVM_TEST_WORK/applied.json"
fi
STUB
chmod +x "$work/bin/kubectl"
export PATH="$work/bin:$PATH"
jq -n '{items:[{metadata:{name:"runner",labels:{"node.cluster.x-k8s.io/pool":"runners-linux","tuist.dev/kata-kvm":"true"},annotations:{"tuist.dev/kata-kvm-config":"revision:boot-1"}},spec:{},status:{nodeInfo:{bootID:"boot-1"},conditions:[{type:"Ready",status:"True"}],allocatable:{pods:"110","devices.tuist.dev/kvm":"110"}}}]}' > "$work/ready.json"
jq -n '[
 {kind:"RunnerPool",spec:{os:"linux",nestedVirtualization:true,fleetSelector:"runners-linux"}},
 {kind:"Deployment",metadata:{name:"provider",labels:{"app.kubernetes.io/component":"capi-scaleway-applesilicon"}},spec:{template:{spec:{containers:[{name:"manager",image:"provider:next"}]}}}},
 ({kind:"ServiceAccount"},{kind:"ClusterRole"},{kind:"ClusterRoleBinding"},{kind:"DaemonSet"} | . + {metadata:{name:"kvm",namespace:"runners",labels:{"app.kubernetes.io/component":"kvm-device-plugin"}}})
]' > "$work/render.json"
cp "$work/ready.json" "$work/nodes.json"
bash "$root/.github/scripts/runner-kvm-prepare.sh" "$work/render.json" tuist tuist-staging
jq -e '(.items | length == 4) and all(.items[]; .metadata.annotations["meta.helm.sh/release-name"] == "tuist" and .metadata.annotations["meta.helm.sh/release-namespace"] == "tuist-staging")' "$work/applied.json" >/dev/null
awk '/set image/ {image=NR} /apply -f/ {plugin=NR} END {exit !(image > 0 && plugin > image)}' "$work/calls"
for mutation in \
 '.items[0].metadata.annotations["tuist.dev/kata-kvm-config"] = "revision:previous-boot"' \
 '.items[0].status.allocatable["devices.tuist.dev/kvm"] = "16"' \
 'del(.items[0].metadata.labels["tuist.dev/kata-kvm"])' \
 '.items[0].status.conditions[0].status = "False"' \
 '.items[0].spec.unschedulable = true'; do
  jq "$mutation" "$work/ready.json" > "$work/nodes.json"
  if KVM_PREPARE_TIMEOUT_SECONDS=0 bash "$root/.github/scripts/runner-kvm-prepare.sh" "$work/render.json" tuist tuist-staging > "$work/out" 2>&1; then
    echo "Gate accepted unsafe state: $mutation" >&2; exit 1
  fi
  grep -q 'runner pools have not been switched' "$work/out"
done
# Rollback skips all preparation, even when hosts are not ready.
jq 'map(if .kind == "RunnerPool" then .spec.nestedVirtualization = false else . end)' "$work/render.json" > "$work/off.json"
: > "$work/calls"
bash "$root/.github/scripts/runner-kvm-prepare.sh" "$work/off.json" tuist tuist-staging
test ! -s "$work/calls"
# First install is left to Helm; no preparatory mutations without hosts.
echo '{"items":[]}' > "$work/nodes.json"
bash "$root/.github/scripts/runner-kvm-prepare.sh" "$work/render.json" tuist tuist-staging
! grep -Eq 'set image|apply -f' "$work/calls"
echo 'KVM preparation preserves pools until hosts and allocations are ready; rollback and first install stay safe.'
