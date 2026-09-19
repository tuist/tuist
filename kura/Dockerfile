# syntax=docker/dockerfile:1.7

FROM rust:1.94.1-bookworm AS build

ARG TARGETARCH

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      build-essential \
      clang \
      cmake \
      pkg-config && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV CARGO_INCREMENTAL=0

COPY Cargo.toml Cargo.lock ./

RUN --mount=type=cache,id=kura-cargo-registry,target=/usr/local/cargo/registry,sharing=locked \
    --mount=type=cache,id=kura-cargo-git,target=/usr/local/cargo/git,sharing=locked \
    mkdir -p src && \
    printf 'fn main() {}\n' > src/main.rs && \
    touch src/lib.rs && \
    cargo fetch --locked && \
    rm -rf src

COPY src src

RUN --mount=type=cache,id=kura-target-${TARGETARCH},target=/app/target,sharing=locked \
    --mount=type=cache,id=kura-cargo-registry,target=/usr/local/cargo/registry,sharing=locked \
    --mount=type=cache,id=kura-cargo-git,target=/usr/local/cargo/git,sharing=locked \
    touch src/lib.rs src/main.rs && \
    cargo build --release --locked && \
    cp /app/target/release/kura /usr/local/bin/kura

FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      tini \
      libstdc++6 && \
    rm -rf /var/lib/apt/lists/*

ENV RUST_LOG=info

WORKDIR /app

COPY --from=build /usr/local/bin/kura /usr/local/bin/kura

EXPOSE 4000

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/kura"]
