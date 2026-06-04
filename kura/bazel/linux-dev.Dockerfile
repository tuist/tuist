# Local Linux build environment for the Kura Bazel migration.
#
# Lets us run Bazel builds/tests against Linux — matching the runtime image's
# Debian Bookworm (glibc 2.36) — from a macOS host via the Docker daemon, without
# going through a GitHub workflow. See docs/bazel-migration-plan.md (Phase 0.3).
#
# The apt packages mirror kura/Dockerfile's build stage (build-essential, clang,
# cmake, pkg-config) for the native -sys crates. crossbuild-essential-{amd64,arm64}
# add the Debian x86_64 and aarch64 cross GCC + sysroots (gcc 12, glibc 2.36,
# libstdc++) so either host can cross-compile the other arch — same toolchain as
# the native build, matching the Bookworm runtime exactly. On each host one is the
# real cross toolchain and the other is redundant. See docs/bazel-migration-plan.md.
#
# Build:  docker build -f bazel/linux-dev.Dockerfile -t kura-bazel-linux .
# Use:    see bazel/linux-build.sh
FROM debian:bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      build-essential \
      clang \
      cmake \
      pkg-config \
      crossbuild-essential-amd64 \
      crossbuild-essential-arm64 \
    && rm -rf /var/lib/apt/lists/*

# Bazelisk reads .bazelversion and fetches the matching Bazel (9.1.0).
RUN arch="$(dpkg --print-architecture)" \
    && curl -fsSL "https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-${arch}" \
       -o /usr/local/bin/bazel \
    && chmod +x /usr/local/bin/bazel

WORKDIR /workspace/kura
