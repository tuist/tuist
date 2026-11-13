#!/usr/bin/env bash
# Exercise the shipped package with real Helm, without registry/cluster access.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
version=0.2.731-2
tag=sha-0123456789ab
digest=sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef

bash "$root/.github/scripts/cloudflare-operator-chart.sh" "$version" "$tag" "$digest" "$work"
archive="$work/cloudflare-operator-$version.tgz"
[[ $(helm show chart "$archive" | yq '.version') == "$version" ]]
[[ $(helm show chart "$archive" | yq '.appVersion') == "$tag" ]]
helm template cloudflare-operator "$archive" > "$work/packaged.yaml"
actual=$(yq 'select(.kind == "Deployment") | .spec.template.spec.containers[0].image' "$work/packaged.yaml")
[[ "$actual" == "ghcr.io/tuist/cloudflare-operator:$tag@$digest" ]]

# Packaging must preserve CRDs, RBAC, token wiring, probes and other defaults.
helm template cloudflare-operator "$root/infra/helm/cloudflare-operator" \
  --set-string "image.tag=$tag" --set-string "image.digest=$digest" > "$work/source.yaml"
yq -o=json -I=0 '.' "$work/packaged.yaml" > "$work/packaged.json"
yq -o=json -I=0 '.' "$work/source.yaml" > "$work/source.json"
diff -u "$work/source.json" "$work/packaged.json"

# Helm's semver resolver must accept the published prerelease using the
# actual Flux selector, rather than silently ignoring all CI releases.
constraint=$(yq 'select(.kind == "HelmRelease") | .spec.chart.spec.version' \
  "$root/infra/flux/cloudflare-operator/helm-release.yaml")
tar -xzf "$archive" -C "$work"
mkdir "$work/consumer"
cat > "$work/consumer/Chart.yaml" <<EOF
apiVersion: v2
name: release-selection-test
version: 1.0.0
dependencies:
  - name: cloudflare-operator
    version: "$constraint"
    repository: file://../cloudflare-operator
EOF
helm dependency update "$work/consumer" --skip-refresh

if bash "$root/.github/scripts/cloudflare-operator-chart.sh" "$version" "$tag" latest "$work"; then
  echo "Packaging must reject a missing/invalid immutable image digest" >&2
  exit 1
fi
echo "Published chart retains the exact image digest and complete operator manifests"
