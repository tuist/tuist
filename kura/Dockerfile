# syntax=docker/dockerfile:1.7

FROM rust:1.94.1-bookworm AS build

ARG TARGETARCH

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      build-essential \
      clang \
      cmake \
      pkg-config ca-certificates && \
    sed -i -e 's|^mozilla/emSign_ECC_Root_CA_-_G3.crt|!&|' -e 's|^mozilla/Comodo_AAA_Services_root.crt|!&|' /etc/ca-certificates.conf && \
    update-ca-certificates && \
    rm -rf /var/lib/apt/lists/*
RUN --mount=type=bind,from=certificate-trust,target=/certificate-trust bash /certificate-trust/pem-store.sh check /etc/ssl/certs/ca-certificates.crt

WORKDIR /app

ENV CARGO_INCREMENTAL=0

COPY Cargo.toml Cargo.lock ./
COPY crates/kura-core/Cargo.toml crates/kura-core/
COPY crates/kura-node/Cargo.toml crates/kura-node/
COPY crates/kura-reapi/Cargo.toml crates/kura-reapi/

RUN --mount=type=cache,id=kura-cargo-registry,target=/usr/local/cargo/registry,sharing=locked \
    --mount=type=cache,id=kura-cargo-git,target=/usr/local/cargo/git,sharing=locked \
    mkdir -p src crates/kura-core/src crates/kura-node/src crates/kura-reapi/src && \
    printf 'fn main() {}\n' > src/main.rs && \
    touch src/lib.rs crates/kura-core/src/lib.rs crates/kura-node/src/lib.rs crates/kura-reapi/src/lib.rs && \
    cargo fetch --locked && \
    rm -rf src crates/kura-core/src crates/kura-node/src crates/kura-reapi/src

COPY src src
COPY crates crates

RUN --mount=type=cache,id=kura-target-${TARGETARCH},target=/app/target,sharing=locked \
    --mount=type=cache,id=kura-cargo-registry,target=/usr/local/cargo/registry,sharing=locked \
    --mount=type=cache,id=kura-cargo-git,target=/usr/local/cargo/git,sharing=locked \
    touch src/lib.rs src/main.rs crates/kura-*/src/lib.rs && \
    cargo build --release --locked && \
    cp /app/target/release/kura /usr/local/bin/kura

FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      tini \
      libstdc++6 && \
    sed -i -e 's|^mozilla/emSign_ECC_Root_CA_-_G3.crt|!&|' -e 's|^mozilla/Comodo_AAA_Services_root.crt|!&|' /etc/ca-certificates.conf && \
    update-ca-certificates && \
    rm -rf /var/lib/apt/lists/*
RUN --mount=type=bind,from=certificate-trust,target=/certificate-trust bash /certificate-trust/pem-store.sh check /etc/ssl/certs/ca-certificates.crt

ENV RUST_LOG=info

WORKDIR /app

COPY --from=build /usr/local/bin/kura /usr/local/bin/kura

EXPOSE 4000

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/kura"]
