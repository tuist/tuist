#!/usr/bin/env bash
#MISE description "Build the Tuist xcresult-processor Tart image locally"
#MISE raw=true
#USAGE arg "<xcode_version>" help="Xcode version of the base macos-tahoe-xcode image (e.g. 26.5, 26.4.1). The tag must already be published — `gh workflow run macos-xcode-image.yml -f xcode_version=...` if not."

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SERVER_DIR="${REPO_ROOT}/server"
PACKER_DIR="${REPO_ROOT}/infra/xcresult-processor-image"
# The base lives on the Tuist OCI registry, which is reachable on the
# tailnet only, so this needs Tailscale up and a registry credential in
# ~/.docker/config.json (`oras login "$TUIST_OCI_REGISTRY_HOST" ...`).
: "${TUIST_OCI_REGISTRY_HOST:?set TUIST_OCI_REGISTRY_HOST (e.g. oci.tuist.dev)}"
BASE_IMAGE="${TUIST_OCI_REGISTRY_HOST}/macos-tahoe-xcode:${usage_xcode_version//./-}"

for cmd in tart packer mix swift; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: ${cmd} is not installed."
    case "$cmd" in
      tart) echo "Install: brew install cirruslabs/cli/tart" ;;
      packer) echo "Install: brew install hashicorp/tap/packer" ;;
    esac
    exit 1
  fi
done

echo "==> Building xcresult NIF..."
"${SERVER_DIR}/native/xcresult_nif/build.sh"

echo "==> Building xcactivitylog NIF..."
"${SERVER_DIR}/native/xcactivitylog_nif/build.sh"

echo "==> Building server release (MIX_ENV=prod)..."
cd "${SERVER_DIR}"
MIX_ENV=prod mix deps.get --only prod
MIX_ENV=prod mix compile --warnings-as-errors
MIX_ENV=prod mix release tuist --overwrite

echo "==> Packaging release tarball..."
RELEASE_TARBALL="$(mktemp -t tuist-release).tar.gz"
trap 'rm -f "$RELEASE_TARBALL"' EXIT
tar -czf "$RELEASE_TARBALL" -C "${SERVER_DIR}/_build/prod/rel/tuist" .
echo "    Tarball: $(ls -lh "$RELEASE_TARBALL" | awk '{print $5}') at $RELEASE_TARBALL"

echo "==> Building Tart image (base: $BASE_IMAGE)..."
cd "${PACKER_DIR}"
packer init xcresult-processor.pkr.hcl
packer build \
  -var "base_image=${BASE_IMAGE}" \
  -var "output_image=tuist-xcresult-processor" \
  -var "release_tarball=${RELEASE_TARBALL}" \
  xcresult-processor.pkr.hcl

echo ""
echo "==> Image 'tuist-xcresult-processor' built. Push with:"
echo "    tart push tuist-xcresult-processor \${TUIST_OCI_REGISTRY_HOST}/tuist-xcresult-processor:latest"
