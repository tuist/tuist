#!/usr/bin/env bash
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export ADOPT_TEST_WORK="$work"
mkdir "$work/bin"
cat > "$work/bin/kubectl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >> "$ADOPT_TEST_WORK/calls"
args=("$@")
for i in "${!args[@]}"; do
  case "${args[$i]}" in
    -n) namespace="${args[$((i + 1))]}" ;;
    get) resource="${args[$((i + 1))]}" ;;
  esac
done
if [[ "$*" == *' get '* ]]; then
  jq --arg resource "$resource" --arg ns "$namespace" '
    [.[] | select(.resource == $resource and (.namespace == $ns or .namespace == null)) | .object] |
      if length == 0 then empty else {kind: "List", items: .} end
  ' "$ADOPT_TEST_WORK/live.json"
fi
STUB
chmod +x "$work/bin/kubectl"
export PATH="$work/bin:$PATH"

owned='{"meta.helm.sh/release-name":"tuist","meta.helm.sh/release-namespace":"tuist-staging"}'
jq -n '[
  {apiVersion:"rbac.authorization.k8s.io/v1",kind:"ClusterRole",metadata:{name:"egress"}},
  {apiVersion:"rbac.authorization.k8s.io/v1",kind:"ClusterRoleBinding",metadata:{name:"egress"}},
  {apiVersion:"v1",kind:"ConfigMap",metadata:{name:"labeled"}},
  {apiVersion:"v1",kind:"ConfigMap",metadata:{name:"foreign",namespace:"kura"}},
  {apiVersion:"v1",kind:"ConfigMap",metadata:{name:"other-release"}},
  {apiVersion:"v1",kind:"Service",metadata:{name:"new"}}
]' > "$work/render.json"
jq -n --argjson owned "$owned" '[
  {resource:"ClusterRole.v1.rbac.authorization.k8s.io",object:{kind:"ClusterRole",metadata:{name:"egress",annotations:$owned}}},
  {resource:"ClusterRoleBinding.v1.rbac.authorization.k8s.io",object:{kind:"ClusterRoleBinding",metadata:{name:"egress",annotations:$owned,labels:{"app.kubernetes.io/managed-by":"kubectl"}}}},
  {resource:"ConfigMap.v1.",namespace:"tuist-staging",object:{kind:"ConfigMap",metadata:{name:"labeled",annotations:$owned,labels:{"app.kubernetes.io/managed-by":"Helm"}}}},
  {resource:"ConfigMap.v1.",namespace:"kura",object:{kind:"ConfigMap",metadata:{name:"foreign"}}},
  {resource:"ConfigMap.v1.",namespace:"tuist-staging",object:{kind:"ConfigMap",metadata:{name:"other-release",annotations:($owned + {"meta.helm.sh/release-name":"tuist-xcresult-processor"})}}}
]' > "$work/live.json"

bash "$root/.github/scripts/helm-adopt-release-objects.sh" "$work/render.json" tuist tuist-staging > "$work/out"

grep -q -- '-n tuist-staging label --overwrite ClusterRole.v1.rbac.authorization.k8s.io egress app.kubernetes.io/managed-by=Helm' "$work/calls"
grep -q -- '-n tuist-staging label --overwrite ClusterRoleBinding.v1.rbac.authorization.k8s.io egress app.kubernetes.io/managed-by=Helm' "$work/calls"
test "$(grep -c ' label ' "$work/calls")" -eq 2
grep -q -- '-n kura get ConfigMap.v1. foreign' "$work/calls"
grep -q -- '-n tuist-staging get Service.v1. new' "$work/calls"

: > "$work/calls"
echo '[]' > "$work/render.json"
bash "$root/.github/scripts/helm-adopt-release-objects.sh" "$work/render.json" tuist tuist-staging
test ! -s "$work/calls"
echo 'Only objects already annotated for this release are labeled for adoption.'
