#!/usr/bin/env bash
#MISE description "Build the Tuist xcresult-processor Tart image locally"
#MISE raw=true
#USAGE arg "[base_image]" help="Override the base Tart image (default: newest published ghcr.io/tuist/macos-tahoe-xcode tag, resolved via `crane ls`). Must already be present in GHCR or your local Tart store."

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SERVER_DIR="${REPO_ROOT}/server"
PACKER_DIR="${REPO_ROOT}/infra/xcresult-processor-image"

for cmd in tart packer mix swift crane; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: ${cmd} is not installed."
    case "$cmd" in
      tart) echo "Install: brew install cirruslabs/cli/tart" ;;
      packer) echo "Install: brew install hashicorp/tap/packer" ;;
      crane) echo "Install: brew install crane" ;;
    esac
    exit 1
  fi
done

# Pick the newest published macos-tahoe-xcode tag at build time. The
# processor parses .xcresult bundles from every customer runner
# profile, so pinning to a specific Xcode would silently break
# parsing of bundles produced by any newer Xcode.
if [ -n "${usage_base_image:-}" ]; then
  BASE_IMAGE="$usage_base_image"
else
  BASE_TAG=$(crane ls ghcr.io/tuist/macos-tahoe-xcode | grep -E '^[0-9]+(-[0-9]+){0,2}$' | sort -t- -k1,1n -k2,2n -k3,3n | tail -n1)
  if [ -z "$BASE_TAG" ]; then
    echo "Error: No version-shaped tags found at ghcr.io/tuist/macos-tahoe-xcode." >&2
    echo "       Trigger macos-xcode-image.yml first, or 'crane auth login ghcr.io' if listing fails." >&2
    exit 1
  fi
  BASE_IMAGE="ghcr.io/tuist/macos-tahoe-xcode:${BASE_TAG}"
fi

echo "==> Building xcresult NIF..."
"${SERVER_DIR}/native/xcresult_nif/build.sh"

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
echo "    tart login ghcr.io"
echo "    tart push tuist-xcresult-processor ghcr.io/tuist/tuist-xcresult-processor:latest"
