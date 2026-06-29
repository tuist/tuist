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
    cargo build --release --locked && \
    cp /app/target/release/kura /usr/local/bin/kura

FROM debian:bookworm-slim AS geoip

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl gzip && \
    rm -rf /var/lib/apt/lists/*

# DB-IP IP-to-City Lite by DB-IP (https://db-ip.com) is licensed under
# Creative Commons Attribution 4.0 International (CC BY 4.0). The free
# monthly dump is published at a predictable URL keyed by year-month; we
# fall back to the previous month if the current one has not been cut yet.
# The City dump carries the ISO 3166-2 subdivision used for finer-grained
# geographic attribution on traces.
RUN set -eux; \
    mkdir -p /opt/geoip; \
    year_month="$(date -u +%Y-%m)"; \
    previous="$(date -u -d 'last month' +%Y-%m 2>/dev/null || date -u -v-1m +%Y-%m)"; \
    for candidate in "$year_month" "$previous"; do \
      url="https://download.db-ip.com/free/dbip-city-lite-${candidate}.mmdb.gz"; \
      if curl -fsSL "$url" -o /tmp/dbip.mmdb.gz; then \
        gunzip -c /tmp/dbip.mmdb.gz > /opt/geoip/dbip-city-lite.mmdb; \
        rm -f /tmp/dbip.mmdb.gz; \
        break; \
      fi; \
    done; \
    test -s /opt/geoip/dbip-city-lite.mmdb

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
COPY --from=geoip /opt/geoip/dbip-city-lite.mmdb /opt/geoip/dbip-city-lite.mmdb

# Bundle the Tuist adopter extension hook so self-hosted nodes (which have no
# controller to render it from a ConfigMap) can enable cache-API auth by
# pointing KURA_EXTENSION_SCRIPT_PATH at this path. It is inert unless the
# extension is enabled; the binary stays generic.
COPY ops/helm/kura/hooks/tuist.lua /etc/kura/extensions/tuist.lua

EXPOSE 4000

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/kura"]
