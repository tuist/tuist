#!/usr/bin/env bash
#
# Build the runtime OCI image with rules_oci, inside the Debian Bookworm dev container,
# with no Docker daemon / Buildx / QEMU. Produces:
#   1. the multi-arch index (//bazel/oci:index) — both Linux arches from this one host,
#   2. a docker-loadable tarball for the NATIVE arch (bazel-dist/kura-oci.tar) that the
#      workflow loads on the host to smoke-test and run the e2e suite against.
#
# The native tarball is built through //bazel/oci:load_linux_<arch>, which reaches the
# image via the SAME transition oci_image_index uses (see bazel/oci/transition.bzl). So
# the native binary is compiled ONCE in the shared transition config and reused by the
# index, instead of a second build under the plain --platforms flag config (which lands
# in a different, non-shared output dir — see docs/bazel-migration-plan.md, "OCI cache
# fragmentation"). Both targets are built in one bazel invocation so they share it.
#
# Invoked by .github/workflows/kura-bazel.yml. SHADOW only: nothing is pushed to a
# registry. See docs/bazel-migration-plan.md (Phase 3.5).
set -euo pipefail

cd /workspace/kura

NATIVE="$(uname -m)"
case "$NATIVE" in
  x86_64) LOAD="//bazel/oci:load_linux_x86_64" ;;
  aarch64) LOAD="//bazel/oci:load_linux_arm64" ;;
  *) echo "unsupported native arch: $NATIVE" >&2; exit 1 ;;
esac

echo "::group::Build multi-arch index + native loadable tarball (shared transition config)"
bazel build -c opt //bazel/oci:index "$LOAD" --output_groups=+tarball
echo "::endgroup::"

mkdir -p bazel-dist
cp -L "bazel-bin/bazel/oci/${LOAD##*:}/tarball.tar" bazel-dist/kura-oci.tar
chmod a+rw bazel-dist/kura-oci.tar
ls -l bazel-dist/kura-oci.tar

echo "OCI build complete."
