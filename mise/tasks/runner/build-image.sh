#!/usr/bin/env bash
#MISE description="Build a Tuist Runner Tart image with GitHub Actions runner pre-installed"
#USAGE arg "<base_image>" help="Base Tart image (e.g. ghcr.io/cirruslabs/macos-tahoe-xcode:26.4)"
#USAGE arg "<output_image>" help="Output image name (e.g. tuist-runner-xcode-26.4)"
#USAGE arg "[runner_version]" help="GitHub Actions runner version (default: 2.333.1)"

set -euo pipefail

readonly BASE_IMAGE="${usage_base_image}"
readonly OUTPUT_IMAGE="${usage_output_image}"
readonly RUNNER_VERSION="${usage_runner_version:-2.333.1}"
readonly PACKER_DIR="${MISE_PROJECT_ROOT}/infra/runner-images"

echo "Building runner image:"
echo "  Base image:      ${BASE_IMAGE}"
echo "  Output image:    ${OUTPUT_IMAGE}"
echo "  Runner version:  ${RUNNER_VERSION}"
echo ""

# Check dependencies
for cmd in tart packer; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "Error: ${cmd} is not installed. Run: brew install cirruslabs/cli/tart hashicorp/tap/packer"
    exit 1
  fi
done

# Initialize and run Packer
cd "${PACKER_DIR}"
packer init runner.pkr.hcl
packer build \
  -var "base_image=${BASE_IMAGE}" \
  -var "output_image=${OUTPUT_IMAGE}" \
  -var "runner_version=${RUNNER_VERSION}" \
  runner.pkr.hcl

echo ""
echo "Image '${OUTPUT_IMAGE}' built successfully."
echo ""
echo "To push to GHCR:"
echo "  tart login ghcr.io"
echo "  tart push ${OUTPUT_IMAGE} ghcr.io/tuist/${OUTPUT_IMAGE}:latest"
