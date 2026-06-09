#!/usr/bin/env bash
# Builds the Vultr CAPI node snapshot with upstream Kubernetes image-builder.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
IMAGE_CATALOG="$REPO_ROOT/infra/k8s/clusters/vultr/images.yaml"
IMAGE_BUILDER_REF="${IMAGE_BUILDER_REF:-main}"
IMAGE_BUILDER_DIR="${IMAGE_BUILDER_DIR:-}"
VULTR_BUILD_REGION="${VULTR_BUILD_REGION:-ewr}"
VULTR_BUILD_PLAN="${VULTR_BUILD_PLAN:-vc2-1c-1gb}"

yaml_value() {
  local key="$1"
  awk -F: -v key="$key" '
    $1 == key {
      value = $0
      sub("^[^:]*:[[:space:]]*", "", value)
      gsub(/^"|"$/, "", value)
      print value
      exit
    }
  ' "$IMAGE_CATALOG"
}

if [ -z "${VULTR_API_KEY:-}" ]; then
  echo "ERROR: VULTR_API_KEY is required" >&2
  exit 1
fi

for tool in curl git jq make; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: missing required tool: $tool" >&2
    exit 1
  fi
done

KUBERNETES_VERSION="$(yaml_value kubernetesVersion)"
UBUNTU_VERSION="$(yaml_value ubuntuVersion)"

case "$UBUNTU_VERSION" in
  22.04) IMAGE_BUILDER_TARGET="build-vultr-ubuntu-2204" ;;
  24.04) IMAGE_BUILDER_TARGET="build-vultr-ubuntu-2404" ;;
  26.04) IMAGE_BUILDER_TARGET="build-vultr-ubuntu-2604" ;;
  *)
    echo "ERROR: unsupported ubuntuVersion '$UBUNTU_VERSION' in $IMAGE_CATALOG" >&2
    exit 64
    ;;
esac

if [ -z "$KUBERNETES_VERSION" ]; then
  echo "ERROR: kubernetesVersion is required in $IMAGE_CATALOG" >&2
  exit 1
fi

WORKDIR=""
if [ -z "$IMAGE_BUILDER_DIR" ]; then
  WORKDIR="$(mktemp -d)"
  trap 'rm -rf "$WORKDIR"' EXIT
  IMAGE_BUILDER_DIR="$WORKDIR/image-builder"
  git clone --depth 1 --branch "$IMAGE_BUILDER_REF" https://github.com/kubernetes-sigs/image-builder.git "$IMAGE_BUILDER_DIR"
fi

cd "$IMAGE_BUILDER_DIR/images/capi"

# image-builder currently carries a Vultr builder `tag` field that the
# current github.com/vultr/vultr Packer plugin rejects as an unknown
# configuration key. The snapshot description already contains the
# Kubernetes/Ubuntu identity we need for discovery, so drop the instance
# tag field before invoking Packer.
awk '
  $0 ~ /^[[:space:]]*"tag":/ { next }
  { print }
' packer/vultr/packer.json > packer/vultr/packer.json.tmp
mv packer/vultr/packer.json.tmp packer/vultr/packer.json

make deps-vultr

PACKER_FLAGS="${PACKER_FLAGS:-} -var kubernetes_semver=${KUBERNETES_VERSION} -var region=${VULTR_BUILD_REGION} -var plan=${VULTR_BUILD_PLAN}"
export PACKER_FLAGS

make "$IMAGE_BUILDER_TARGET"

echo
echo "Recent matching Vultr snapshots:"
curl -fsSL \
  -H "Authorization: Bearer ${VULTR_API_KEY}" \
  https://api.vultr.com/v2/snapshots |
  jq -r --arg k8s "$KUBERNETES_VERSION" --arg ubuntu "$UBUNTU_VERSION" '
    .snapshots[]
    | select((.description // "") | contains("Cluster API Kubernetes " + $k8s))
    | select((.description // "") | contains("Ubuntu " + $ubuntu))
    | [.id, .date_created, .description]
    | @tsv
  '

cat <<EOF

Commit the selected snapshot ID to:
  $IMAGE_CATALOG

Field:
  snapshotID: "<snapshot-id>"
EOF
