#!/usr/bin/env bash
#MISE description "Build the Tuist xcresult-processor Tart image locally"
#MISE raw=true
#USAGE arg "<xcode_version>" help="Xcode version of the base macos-tahoe-xcode image (e.g. 26.5, 26.4.1). The tag must already be published — `gh workflow run macos-xcode-image.yml -f xcode_version=...` if not."

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
PACKER_DIR="${REPO_ROOT}/infra/xcresult-processor-image"
# The base lives on the Tuist OCI registry, which is reachable on the
# tailnet only, so this needs Tailscale up and a registry credential in
# ~/.docker/config.json (`oras login "$TUIST_OCI_REGISTRY_HOST" ...`).
: "${TUIST_OCI_REGISTRY_HOST:?set TUIST_OCI_REGISTRY_HOST (e.g. oci.tuist.dev)}"
BASE_IMAGE="${TUIST_OCI_REGISTRY_HOST}/macos-tahoe-xcode:${usage_xcode_version//./-}"

for cmd in tart packer; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: ${cmd} is not installed."
    case "$cmd" in
      tart) echo "Install: brew install cirruslabs/cli/tart" ;;
      packer) echo "Install: brew install hashicorp/tap/packer" ;;
    esac
    exit 1
  fi
done

echo "==> Building Tart image (base: $BASE_IMAGE)..."
cd "${PACKER_DIR}"
packer init xcresult-processor.pkr.hcl
packer build \
  -var "base_image=${BASE_IMAGE}" \
  -var "output_image=tuist-xcresult-processor" \
  xcresult-processor.pkr.hcl

echo ""
echo "==> Image 'tuist-xcresult-processor' built. Push with:"
echo "    tart push tuist-xcresult-processor \${TUIST_OCI_REGISTRY_HOST}/tuist-xcresult-processor:latest"
