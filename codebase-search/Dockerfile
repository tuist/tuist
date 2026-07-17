# syntax=docker/dockerfile:1.7

FROM rust:1.94.1-bookworm AS builder

WORKDIR /app
ENV CARGO_INCREMENTAL=0

COPY Cargo.toml Cargo.lock ./
RUN --mount=type=cache,id=codebase-search-cargo-registry,target=/usr/local/cargo/registry,sharing=locked \
    mkdir src && \
    printf 'fn main() {}\n' > src/main.rs && \
    touch src/lib.rs && \
    cargo fetch --locked && \
    rm -rf src

COPY src src
RUN --mount=type=cache,id=codebase-search-target,target=/app/target,sharing=locked \
    --mount=type=cache,id=codebase-search-cargo-registry,target=/usr/local/cargo/registry,sharing=locked \
    cargo build --release --locked && \
    cp target/release/tuist-codebase-search /usr/local/bin/tuist-codebase-search

FROM debian:bookworm-slim AS source

ARG TUIST_REVISION

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates git && \
    rm -rf /var/lib/apt/lists/* && \
    echo "${TUIST_REVISION}" | grep -Eq '^[0-9a-f]{40}$' && \
    git init /workspace && \
    git -C /workspace remote add origin https://github.com/tuist/tuist.git && \
    git -C /workspace fetch --depth=1 origin "${TUIST_REVISION}" && \
    git -C /workspace checkout --detach FETCH_HEAD && \
    test "$(git -C /workspace rev-parse HEAD)" = "${TUIST_REVISION}" && \
    rm -rf /workspace/.git

FROM debian:bookworm-slim

ARG TUIST_REVISION

RUN apt-get update && \
    apt-get install -y --no-install-recommends tini && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd --gid 990 codebase && \
    useradd --uid 990 --gid codebase --no-create-home codebase

COPY --from=builder /usr/local/bin/tuist-codebase-search /usr/local/bin/tuist-codebase-search
COPY --from=source /workspace /workspace

ENV CODEBASE_BIND_ADDRESS=0.0.0.0:4000
ENV CODEBASE_REPOSITORY_URL=https://github.com/tuist/tuist
ENV CODEBASE_REVISION=${TUIST_REVISION}
ENV CODEBASE_ROOT=/workspace
ENV RUST_LOG=info

USER codebase
EXPOSE 4000

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/tuist-codebase-search"]
