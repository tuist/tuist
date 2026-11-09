# syntax=docker/dockerfile:1
#
# Multi-arch image for `condukt-egress`. Used as both the init container
# (in `netfilter-setup` mode) and the sidecar (in `proxy` mode) for
# `Condukt.Sandbox.NetworkPolicy`-enabled `Condukt.Sandbox.Kubernetes`
# pods.
#
# We use `debian:bookworm-slim` as the runtime base rather than
# `gcr.io/distroless/cc-debian12` for v1. The init mode needs the
# `iptables` binary (and its shared-library dependency closure:
# libnftnl, libmnl, libxtables, libnetfilter-conntrack, libnfnetlink),
# which distroless does not provide. Multi-stage copy of the iptables
# dep closure into distroless is fragile across Debian versions; we
# accept a slightly larger image (~85MB) for v1 to keep this Dockerfile
# stable. Future revision: switch to distroless+manual lib copy once
# we have CI coverage that catches missing-lib regressions.

# cargo-chef caches the compiled dependency closure (rustls, tokio,
# hyper, rcgen, ...) in a layer keyed only by the dependency graph, so
# source-only edits reuse it instead of rebuilding from scratch on
# every CI run. We use cargo-chef rather than the "stub main" trick
# because that trick relies on file mtimes: after COPYing real sources,
# cargo can see the stub-built artifact as newer than the sources and
# skip the real rebuild, shipping a do-nothing binary. cargo-chef never
# builds the bin in the cook step, so there is no stale fingerprint.
# The `cargo install` layer is keyed on the base image alone.
FROM rust:1.94-bookworm AS chef
RUN cargo install cargo-chef --locked
WORKDIR /src

FROM chef AS planner
COPY Cargo.toml Cargo.lock rust-toolchain.toml ./
COPY src ./src
RUN cargo chef prepare --recipe-path recipe.json

FROM chef AS builder
COPY --from=planner /src/recipe.json recipe.json
# Dependency-only build. Cached until recipe.json (the dependency
# graph) changes; gha cache-to/from is wired in the workflow.
RUN cargo chef cook --release --recipe-path recipe.json
COPY Cargo.toml Cargo.lock rust-toolchain.toml ./
COPY src ./src
RUN cargo build --release --frozen \
 && strip target/release/condukt-egress

# ----------------------------------------------------------------------------

FROM debian:bookworm-slim AS runtime

# `iptables-nft` is the default backend on modern Debian and what we
# rely on at runtime. `ca-certificates` is needed for the
# TLS-terminating path: the sidecar dials upstream TLS and verifies the
# real server's cert against the system trust store.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      iptables \
      ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Sidecar runs as a fixed uid so the init container's netfilter rule
# can exempt it by `--uid-owner`.
RUN groupadd --system --gid 1337 condukt-egress \
 && useradd --system --uid 1337 --gid 1337 --no-create-home --shell /sbin/nologin condukt-egress

COPY --from=builder /src/target/release/condukt-egress /usr/local/bin/condukt-egress

# Default to the proxy subcommand so the sidecar usage path is the
# zero-config one. The K8s init container overrides `command:` to run
# `condukt-egress netfilter-setup`.
USER 1337
ENTRYPOINT ["/usr/local/bin/condukt-egress"]
CMD ["proxy"]
