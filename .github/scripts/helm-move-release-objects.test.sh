#!/usr/bin/env bash
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export MOVE_TEST_WORK="$work"
mkdir "$work/bin"
cat > "$work/bin/kubectl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >> "$MOVE_TEST_WORK/calls"
args=("$@")
for i in "${!args[@]}"; do
  case "${args[$i]}" in
    -n) namespace="${args[$((i + 1))]}" ;;
    get) resource="${args[$((i + 1))]}"; name="${args[$((i + 2))]}" ;;
  esac
done
if [[ "$*" == *' get '* ]]; then
  jq --arg resource "$resource" --arg ns "$namespace" --arg name "$name" '
    .[] | select(.resource == $resource and .namespace == $ns and .object.metadata.name == $name) | .object
  ' "$MOVE_TEST_WORK/live.json"
fi
STUB
chmod +x "$work/bin/kubectl"
export PATH="$work/bin:$PATH"

owner() { jq -nc --arg release "$1" --arg ns "${2:-tuist-staging}" '{"meta.helm.sh/release-name":$release,"meta.helm.sh/release-namespace":$ns}'; }
jq -n '[
  {apiVersion:"apps/v1",kind:"DaemonSet",metadata:{name:"kura-volumes-csi-node",namespace:"kura-volumes"}},
  {apiVersion:"apps/v1",kind:"DaemonSet",metadata:{name:"kura-volumes-csi-rack",namespace:"kura-volumes"}},
  {apiVersion:"apps/v1",kind:"DaemonSet",metadata:{name:"foreign",namespace:"kura-volumes"}},
  {apiVersion:"apps/v1",kind:"DaemonSet",metadata:{name:"other-namespace",namespace:"kura-volumes"}},
  {apiVersion:"v1",kind:"ConfigMap",metadata:{name:"new"}}
]' > "$work/render.json"
jq -n --argjson main "$(owner tuist)" --argjson rack "$(owner tuist-rack-nodes)" \
  --argjson foreign "$(owner tuist-xcresult-processor)" --argjson elsewhere "$(owner tuist tuist-canary)" '[
  {resource:"DaemonSet.v1.apps",namespace:"kura-volumes",object:{metadata:{name:"kura-volumes-csi-node",annotations:$main,labels:{"app.kubernetes.io/managed-by":"Helm"}}}},
  {resource:"DaemonSet.v1.apps",namespace:"kura-volumes",object:{metadata:{name:"kura-volumes-csi-rack",annotations:$rack}}},
  {resource:"DaemonSet.v1.apps",namespace:"kura-volumes",object:{metadata:{name:"foreign",annotations:$foreign}}},
  {resource:"DaemonSet.v1.apps",namespace:"kura-volumes",object:{metadata:{name:"other-namespace",annotations:$elsewhere}}}
]' > "$work/live.json"

bash "$root/.github/scripts/helm-move-release-objects.sh" "$work/render.json" tuist tuist-rack-nodes tuist-staging > "$work/out"

grep -q -- '-n kura-volumes annotate --overwrite DaemonSet.v1.apps kura-volumes-csi-node meta.helm.sh/release-name=tuist-rack-nodes meta.helm.sh/release-namespace=tuist-staging' "$work/calls"
grep -q -- '-n kura-volumes label --overwrite DaemonSet.v1.apps kura-volumes-csi-node app.kubernetes.io/managed-by=Helm' "$work/calls"
test "$(grep -c ' annotate ' "$work/calls")" -eq 1
test "$(grep -c ' label ' "$work/calls")" -eq 1
grep -q -- '-n tuist-staging get ConfigMap.v1. new' "$work/calls"
echo 'Only objects the previous release owns in this namespace move to the new release.'
