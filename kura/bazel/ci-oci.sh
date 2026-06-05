#!/usr/bin/env bash
#
# Build the runtime OCI image with rules_oci, inside the Debian Bookworm dev container,
# with no Docker daemon / Buildx / QEMU. Produces:
#   1. the multi-arch index (//bazel/oci:index) — both Linux arches from this one host,
#   2. a docker-loadable tarball for the NATIVE arch (bazel-dist/kura-oci.tar) that the
#      workflow loads on the host to smoke-test and run the e2e suite against.
#
# Invoked by .github/workflows/kura-bazel.yml. SHADOW only: nothing is pushed to a
# registry. See docs/bazel-migration-plan.md (Phase 3.5).
set -euo pipefail

cd /workspace/kura

NATIVE="$(uname -m)"
case "$NATIVE" in
  x86_64) PLATFORM="//bazel/platforms:linux_x86_64" ;;
  aarch64) PLATFORM="//bazel/platforms:linux_arm64" ;;
  *) echo "unsupported native arch: $NATIVE" >&2; exit 1 ;;
esac

# Native image + tarball first, so the e2e image is ready; the index reuses the native
# arch and adds the cross arch.
echo "::group::Export native ($NATIVE) image tarball"
bazel build -c opt //bazel/oci:load --output_groups=tarball --platforms="$PLATFORM"
mkdir -p bazel-dist
cp -L bazel-bin/bazel/oci/load/tarball.tar bazel-dist/kura-oci.tar
chmod a+rw bazel-dist/kura-oci.tar
ls -l bazel-dist/kura-oci.tar
echo "::endgroup::"

echo "::group::Build multi-arch index (both arches, one host, no QEMU)"
bazel build -c opt //bazel/oci:index
echo "::endgroup::"

echo "OCI build complete."
