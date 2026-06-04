#!/usr/bin/env bash
#
# Cross-build kura for both Linux arches with Bazel and validate the binaries from
# inside the Debian Bookworm dev container (bazel/linux-dev.Dockerfile), so the
# cross GCC, libstdc++, and the glibc 2.36 floor all match the runtime image exactly.
#
# Invoked by .github/workflows/kura-bazel.yml; also runnable locally:
#   docker build -f bazel/linux-dev.Dockerfile -t kura-bazel-dev .
#   docker run --rm -v "$PWD:/workspace/kura" kura-bazel-dev bash bazel/ci-validate.sh
#
# On each host one arch is native (autodetected host cc) and the other is cross
# (Debian cross GCC), because the cross toolchains are scoped by exec arch. Building
# BOTH here proves the symmetric toolchains and that a single host can emit both
# arches — the input the multi-arch OCI image needs (Phase 3). See
# docs/bazel-migration-plan.md.
set -euo pipefail

cd /workspace/kura

readonly MAX_GLIBC="2.36"          # Debian Bookworm runtime floor.
readonly BUILD_FLAGS="-c opt"      # Match the release (cargo build --release) profile.
readonly NATIVE="$(uname -m)"      # x86_64 or aarch64 — the only directly runnable arch.
readonly DIST="bazel-dist"         # Ignored by .gitignore's /bazel-* rule.

declare -A PLATFORM=(
  [x86_64]="//bazel/platforms:linux_x86_64"
  [aarch64]="//bazel/platforms:linux_arm64"
)
declare -A MACHINE_RE=(
  [x86_64]="X86-64"
  [aarch64]="AArch64"
)

mkdir -p "$DIST"

build_and_validate() {
  local arch="$1" platform="${PLATFORM[$1]}" bin maxver

  echo "::group::Build kura ($arch) via $platform"
  bazel build $BUILD_FLAGS //:kura --platforms="$platform"
  bin="$(bazel cquery $BUILD_FLAGS --output=files //:kura --platforms="$platform" 2>/dev/null \
    | grep -E '/kura$' | head -1)"
  if [ -z "$bin" ] || [ ! -e "$bin" ]; then
    echo "could not locate the built binary for $arch" >&2
    exit 1
  fi
  install -m 0755 "$bin" "$DIST/kura-$arch"
  echo "::endgroup::"

  echo "--- validate $arch ---"
  readelf -h "$DIST/kura-$arch" | grep -E 'Class|Machine'
  if ! readelf -h "$DIST/kura-$arch" | grep -q "${MACHINE_RE[$arch]}"; then
    echo "ELF machine is not ${MACHINE_RE[$arch]} for $arch" >&2
    exit 1
  fi

  # The runtime is Bookworm (glibc 2.36); a higher floor would fail to start there.
  maxver="$(readelf -V "$DIST/kura-$arch" | grep -oE 'GLIBC_[0-9]+\.[0-9]+' \
    | sed 's/GLIBC_//' | sort -uV | tail -1)"
  echo "max referenced glibc: ${maxver:-none} (must be <= $MAX_GLIBC)"
  if [ -n "$maxver" ] \
    && [ "$(printf '%s\n%s\n' "$maxver" "$MAX_GLIBC" | sort -V | tail -1)" != "$MAX_GLIBC" ]; then
    echo "glibc floor $maxver exceeds the runtime's $MAX_GLIBC" >&2
    exit 1
  fi

  sha256sum "$DIST/kura-$arch" | awk -v f="kura-$arch" '{print $1"  "f}' > "$DIST/kura-$arch.sha256"
}

for arch in x86_64 aarch64; do
  build_and_validate "$arch"
done

# The native binary is the only one this host can execute. Run it with an empty
# environment: it must reach config parsing and fail cleanly (proving the dynamic
# loader, jemalloc allocator, and tokio runtime all initialize), not crash.
echo "::group::Smoke-run native binary ($NATIVE)"
ldd "$DIST/kura-$NATIVE"
set +e
output="$(timeout 30s env -i "./$DIST/kura-$NATIVE" 2>&1)"
code=$?
set -e
echo "exit code: $code"
echo "$output"
if ! echo "$output" | grep -Eq "invalid configuration|missing required"; then
  echo "native binary did not start cleanly (expected a config error)" >&2
  exit 1
fi
echo "::endgroup::"

chmod -R a+rX "$DIST"
echo
echo "Bazel binary validation passed:"
ls -l "$DIST"
