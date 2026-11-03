#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir "$fixture/bin"
cat > "$fixture/bin/kubectl" <<'SH'
#!/usr/bin/env bash
test "${API_FAIL:-false}" != true || exit 1
if [ "$1" = get ]; then
  if [ "${NAMESPACE_EXISTS:-true}" = true ]; then echo namespace/kura-volumes; fi
  exit 0
fi
jq -n --arg image "${CURRENT_IMAGE:-}" '{items: (if $image == "" then [] else [{spec:{template:{spec:{containers:[{name:"driver",image:$image}]}}}}] end)}'
SH
cat > "$fixture/bin/docker" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$MANIFEST_CALLS"
test "${MANIFEST_FAIL:-false}" != true
SH
chmod +x "$fixture/bin/"*
export PATH="$fixture/bin:$PATH" GITHUB_ENV="$fixture/env" MANIFEST_CALLS="$fixture/manifests"
export CURRENT_IMAGE="" KURA_VOLUMES_CSI_IMAGE_DIGEST_INPUT="" API_FAIL=false MANIFEST_FAIL=false
run() { : > "$GITHUB_ENV"; bash "$root/kura-csi-image.sh"; }
run
grep -qx 'KURA_VOLUMES_CSI_IMAGE_TAG=' "$GITHUB_ENV"
export NAMESPACE_EXISTS=false
run
grep -qx 'KURA_VOLUMES_CSI_IMAGE_DIGEST=' "$GITHUB_ENV"
export NAMESPACE_EXISTS=true
export CURRENT_IMAGE=ghcr.io/tuist/kura-volumes-csi:sha-old
run
grep -qx 'KURA_VOLUMES_CSI_IMAGE_TAG=sha-old' "$GITHUB_ENV"
test ! -f "$MANIFEST_CALLS"
export API_FAIL=true
if run; then echo 'API failure was treated as absence' >&2; exit 1; fi
test ! -s "$GITHUB_ENV"
export API_FAIL=false
KURA_VOLUMES_CSI_IMAGE_DIGEST_INPUT="sha256:$(printf 'a%.0s' {1..64})"
export KURA_VOLUMES_CSI_IMAGE_DIGEST_INPUT
run
grep -qx "KURA_VOLUMES_CSI_IMAGE_DIGEST=$KURA_VOLUMES_CSI_IMAGE_DIGEST_INPUT" "$GITHUB_ENV"
export MANIFEST_FAIL=true
if run; then echo 'Missing image accepted' >&2; exit 1; fi
test ! -s "$GITHUB_ENV"
export MANIFEST_FAIL=false KURA_VOLUMES_CSI_IMAGE_DIGEST_INPUT=latest
if run; then echo 'Mutable upgrade accepted' >&2; exit 1; fi
export KURA_VOLUMES_CSI_IMAGE_DIGEST_INPUT="" CURRENT_IMAGE=other/image:tag
if run; then echo 'Unknown driver discarded' >&2; exit 1; fi
echo 'CSI image selection tests passed'
