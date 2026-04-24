ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28.4.3
# hexpm/elixir uses date-pinned tags; their specific bookworm tag has both
# linux/amd64 and linux/arm64/v8 manifests so the builder stage is multi-arch.
ARG DEBIAN_BUILDER_VERSION=bookworm-20260406-slim
# The plain debian:bookworm-20260406-slim tag is amd64-only. Use the unpinned
# bookworm-slim tag for the runner base so the final image supports both
# amd64 and arm64. Trading a small amount of reproducibility for multi-arch.
ARG DEBIAN_RUNNER_VERSION=bookworm-slim
ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_BUILDER_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_RUNNER_VERSION}"

# ========================================
# Stage: Swift NIF builder
# Only built when referenced by selfhosted target (BuildKit skips otherwise)
# ========================================
FROM swift:6.2-bookworm AS swift-builder

RUN apt-get update -qq && apt-get install -y -qq unzip > /dev/null 2>&1 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /nif

COPY processor/native/xcactivitylog_nif/Package.swift .
COPY processor/native/xcactivitylog_nif/Package.resolved .
COPY processor/native/xcactivitylog_nif/Sources/ Sources/
COPY processor/native/xcactivitylog_nif/Tests/ Tests/
COPY processor/native/xcactivitylog_nif/.swiftpm/ .swiftpm/

RUN swift build -c release --replace-scm-with-registry && \
    cp .build/release/libXCActivityLogNIF.so /nif/libXCActivityLogNIF.so && \
    mkdir -p /nif/swift-libs && \
    cp -a /usr/lib/swift/linux/lib*.so* /nif/swift-libs/

# ========================================
# Stage 1: NPM dependencies
# ========================================
FROM node:22-slim AS npm-deps
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable
COPY server/package.json /app/package.json
COPY server/pnpm-lock.yaml /app/pnpm-lock.yaml
WORKDIR /app
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile

# Build noora static assets (JS + CSS) from source
COPY noora /noora
WORKDIR /noora
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install
RUN npx esbuild js/index.js --bundle --minify --sourcemap --format=esm --outfile=./priv/static/noora.js && \
    npx esbuild css/noora.css --bundle --minify --sourcemap --outfile=./priv/static/noora.css
WORKDIR /app

# ========================================
# Stage 2: Base dependencies builder
# ========================================
FROM ${BUILDER_IMAGE} AS deps-builder

RUN apt-get update -y && apt-get upgrade -y && apt-get install -y build-essential git \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

RUN mix local.hex --force && \
  mix local.rebar --force

ARG MIX_ENV=prod
ENV MIX_ENV=$MIX_ENV
ARG TUIST_HOSTED=1
ENV TUIST_HOSTED=$TUIST_HOSTED

# Longer per-request hex.pm timeout to absorb transient network hiccups
# during the first resolver fetch. No measurable effect on fast networks.
ENV HEX_HTTP_TIMEOUT=120

COPY server/mix.exs server/mix.lock ./
RUN mkdir config

# Copy path dependencies (only mix.exs/mix.lock for dep resolution)
COPY tuist_common /tuist_common
COPY noora /noora
COPY processor/mix.exs processor/mix.lock /processor/
COPY xcode_processor/mix.exs xcode_processor/mix.lock /xcode_processor/
COPY xcode_processor/config /xcode_processor/config

# Retry deps.get up to 3 times — hex.pm resolver can fall through to an empty
# local cache on network flakes, producing "Unknown package in lockfile"
# errors on packages that clearly exist in mix.lock. Exit non-zero if every
# attempt fails (the naive `|| sleep && break` form was masking failures).
# Cache mounts for hex/rebar stores speed up redownloads when mix.lock changes.
RUN --mount=type=cache,id=mix-hex,target=/root/.hex \
    --mount=type=cache,id=mix-rebar3,target=/root/.cache/rebar3 \
    set -e; \
    attempts=0; \
    until mix deps.get --only $MIX_ENV; do \
      attempts=$((attempts + 1)); \
      if [ $attempts -ge 3 ]; then \
        echo "mix deps.get failed after $attempts attempts" >&2; \
        exit 1; \
      fi; \
      sleep 5; \
    done

# Config files must be present before compiling dependencies
COPY server/config/config.exs server/config/${MIX_ENV}.exs config/

# Copy path dependency sources for compilation
COPY processor/lib /processor/lib
COPY xcode_processor/lib /xcode_processor/lib

# Cache mount on _build persists compiled dep artifacts across builds, so
# incremental compilation survives even when this layer is invalidated.
# The mount masks the image layer, so /app/_build is empty in the committed
# layer — every subsequent RUN that reads _build must use the same mount id.
RUN --mount=type=cache,id=mix-build,target=/app/_build \
    mix deps.compile

# ========================================
# Stage 3: Main application builder
# ========================================
FROM deps-builder AS builder

COPY server/priv priv
COPY skills/skills priv/static/skills
COPY server/assets assets

# Xcode example READMEs needed at compile time by Tuist.Docs.Loader
COPY examples/xcode /examples/xcode

COPY server/lib lib

# Install Chromium before the big mix RUN so it can generate OG images.
# Kept in its own layer (no mix mount needed) so it caches independently
# of source changes, and runs before mix compile so the compile RUN
# doesn't interleave apt-get network I/O with Elixir compilation.
RUN apt-get update -y && \
  apt-get install -y --no-install-recommends chromium fonts-noto-cjk fonts-noto-core && \
  apt-get clean && rm -rf /var/lib/apt/lists/*

# All mix steps that read/write _build share the same cache mount id so
# incremental compilation persists both within this build (across RUNs)
# and across builds (via BuildKit persistent cache).
RUN --mount=type=cache,id=mix-build,target=/app/_build \
    mix compile --warnings-as-errors

RUN --mount=type=cache,id=mix-build,target=/app/_build \
    mix docs.gen.og_images
RUN --mount=type=cache,id=mix-build,target=/app/_build \
    mix marketing.gen.og_images

COPY server/config/runtime.exs config/
COPY server/rel rel

COPY --from=npm-deps /app/node_modules /app/node_modules
COPY --from=npm-deps /noora/priv/static /noora/priv/static
RUN --mount=type=cache,id=mix-build,target=/app/_build \
    mix assets.deploy

# mix release writes into the cache mount, so we copy the release output
# out to /release (a real image path) in the same RUN. Downstream stages
# COPY --from=builder /release instead of /app/_build/${MIX_ENV}/rel/tuist.
RUN --mount=type=cache,id=mix-build,target=/app/_build \
    mix release && \
    cp -r /app/_build/${MIX_ENV}/rel/tuist /release

# ========================================
# Stage: NIF bridge builder (for selfhosted)
# Compiles the C NIF bridge linking against the Swift library
# ========================================
FROM builder AS nif-bridge-builder

COPY processor/native/xcactivitylog_nif/nif_bridge.c /tmp/nif/nif_bridge.c
COPY --from=swift-builder /nif/libXCActivityLogNIF.so /tmp/nif/libXCActivityLogNIF.so

RUN mkdir -p /release/lib/processor-0.1.0/priv/native && \
    ERL_INCLUDE=$(erl -eval 'io:format("~s/erts-~s/include", [code:root_dir(), erlang:system_info(version)])' -s init stop -noshell) && \
    cc -shared -fPIC \
      -o /release/lib/processor-0.1.0/priv/native/xcactivitylog_nif.so \
      /tmp/nif/nif_bridge.c \
      -I"$ERL_INCLUDE" \
      -L/tmp/nif \
      -lXCActivityLogNIF \
      -Wl,-rpath,'$ORIGIN' && \
    cp /tmp/nif/libXCActivityLogNIF.so /release/lib/processor-0.1.0/priv/native/

# ========================================
# Stage 5: Common runtime base
# ========================================
FROM ${RUNNER_IMAGE} AS runner-base

# APT_CACHE_BUST is passed from CI (e.g. the commit SHA) to invalidate the
# apt layer so `apt-get upgrade` picks up the latest security patches instead
# of reusing a stale cached layer.
ARG APT_CACHE_BUST=0
RUN : "APT_CACHE_BUST=${APT_CACHE_BUST}" \
  && apt-get update -y && \
  apt-get upgrade -y && \
  apt-get install -y curl build-essential gcc wget libvips libstdc++6 openssl libncurses5 locales ca-certificates postgresql-client zip unzip git tini \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

ARG MIX_ENV=prod
ARG TUIST_HOSTED=1
ARG EMBED_CLICKHOUSE=false
ENV MIX_ENV=$MIX_ENV
ENV TUIST_HOSTED=$TUIST_HOSTED

COPY --from=builder --chown=nobody:root /release ./

COPY server/priv/secrets/can.yml.enc /app/priv/secrets/can.yml.enc
COPY server/priv/secrets/stag.yml.enc /app/priv/secrets/stag.yml.enc
COPY server/priv/secrets/prod.yml.enc /app/priv/secrets/prod.yml.enc

# For non-hosted builds (previews/self-hosted): remove encrypted secrets
RUN if [ "$TUIST_HOSTED" = "0" ]; then \
  rm -rf /app/priv/secrets/can.yml.enc; \
  rm -rf /app/priv/secrets/stag.yml.enc; \
  rm -rf /app/priv/secrets/prod.yml.enc; \
  fi

# Optionally embed ClickHouse for environments without a separate ClickHouse service
# (e.g. preview environments). Set EMBED_CLICKHOUSE=true to enable.
RUN if [ "$EMBED_CLICKHOUSE" = "true" ]; then \
  echo "Installing embedded ClickHouse..."; \
  curl -fsSL 'https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml.key' | gpg --dearmor -o /usr/share/keyrings/clickhouse-keyring.gpg && \
  echo "deb [signed-by=/usr/share/keyrings/clickhouse-keyring.gpg] https://packages.clickhouse.com/deb stable main" > /etc/apt/sources.list.d/clickhouse.list && \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install -y clickhouse-server clickhouse-client && \
  apt-get clean && rm -rf /var/lib/apt/lists/* && \
  mkdir -p /var/lib/clickhouse/coordination/log /var/lib/clickhouse/coordination/snapshots && \
  chown -R nobody:nogroup /var/lib/clickhouse /var/log/clickhouse-server /etc/clickhouse-server; \
  fi

COPY server/clickhouse-preview-config.xml /tmp/clickhouse-preview-config.xml
RUN if [ "$EMBED_CLICKHOUSE" = "true" ]; then \
  cp /tmp/clickhouse-preview-config.xml /etc/clickhouse-server/config.d/preview.xml; \
  fi && rm -f /tmp/clickhouse-preview-config.xml

ENV SECRETS_DIRECTORY=/app/priv/secrets/
COPY server/priv/repo/structure.sql /app/priv/repo/structure.sql

# ========================================
# Stage: Self-hosted runtime — includes Swift NIF
# Build with: docker build --target runner-selfhosted .
# ========================================
FROM runner-base AS runner-selfhosted

# Swift runtime libraries needed by the NIF
COPY --from=swift-builder /nif/swift-libs/ /usr/local/lib/
RUN ldconfig

# Copy compiled NIF .so files into processor priv dir
COPY --from=nif-bridge-builder /release/lib/processor-0.1.0/priv/native/ /app/lib/processor-0.1.0/priv/native/

USER nobody

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8080/ready || exit 1

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["sh", "-c", "/app/bin/start"]

# ========================================
# Stage: Default runtime (hosted) — no Swift NIF
# BuildKit skips swift-builder since it's not referenced by this target
# This must be the LAST stage so it's the default docker build target
# ========================================
FROM runner-base AS runner

USER nobody

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8080/ready || exit 1

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["sh", "-c", "/app/bin/start"]
