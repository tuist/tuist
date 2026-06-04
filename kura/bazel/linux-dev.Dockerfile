# Local Linux build environment for the Kura Bazel migration.
#
# Lets us run Bazel builds/tests against Linux — matching the runtime image's
# Debian Bookworm (glibc 2.36) — from a macOS host via the Docker daemon, without
# going through a GitHub workflow. See docs/bazel-migration-plan.md (Phase 0.3).
#
# The apt packages mirror kura/Dockerfile's build stage: the native -sys crates
# (rocksdb, jemalloc, lua) run their build scripts against these host tools for
# now; Phase 0.4 replaces them with a hermetic toolchain.
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
    && rm -rf /var/lib/apt/lists/*

# Bazelisk reads .bazelversion and fetches the matching Bazel (9.1.0).
RUN arch="$(dpkg --print-architecture)" \
    && curl -fsSL "https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-${arch}" \
       -o /usr/local/bin/bazel \
    && chmod +x /usr/local/bin/bazel

WORKDIR /workspace/kura
