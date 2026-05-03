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
# Builds the native xcactivitylog parser. The result is linked into the
# Elixir release via the C bridge in Stage `nif-bridge-builder` below, and
# bundled into every runtime image — the same release boots as the web
# server or as an Oban processor pod depending on TUIST_PROCESSOR_MODE.
# ========================================
FROM swift:6.2-bookworm AS swift-builder

RUN apt-get update -qq && apt-get install -y -qq unzip > /dev/null 2>&1 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /nif

COPY server/native/xcactivitylog_nif/Package.swift .
COPY server/native/xcactivitylog_nif/Package.resolved .
COPY server/native/xcactivitylog_nif/Sources/ Sources/
COPY server/native/xcactivitylog_nif/Tests/ Tests/
COPY server/native/xcactivitylog_nif/.swiftpm/ .swiftpm/

RUN swift build -c release --replace-scm-with-registry && \
    cp .build/release/libXCActivityLogNIF.so /nif/libXCActivityLogNIF.so && \
    mkdir -p /nif/swift-libs && \
    cp -a /usr/lib/swift/linux/lib*.so* /nif/swift-libs/

# ========================================
# Stage 1: NPM dependencies
# ========================================
FROM node:22-slim AS npm-deps
ENV CI=1
ENV XDG_DATA_HOME="/aube-data"
RUN npm install -g --ignore-scripts=false @endevco/aube
COPY server/package.json /app/package.json
COPY server/pnpm-lock.yaml /app/pnpm-lock.yaml
WORKDIR /app
RUN --mount=type=cache,id=aube,target=/aube-data/aube aube install --frozen-lockfile

# Build noora static assets (JS + CSS) from source
COPY noora /noora
WORKDIR /noora
RUN --mount=type=cache,id=aube,target=/aube-data/aube aube install
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

# Config files must be present before compiling dependencies. All three
# managed envs (prod/can/stag) ship in the image so the runtime can
# select one via TUIST_DEPLOY_ENV, but only ${MIX_ENV}.exs is actually
# imported at compile time by config/config.exs.
COPY server/config/config.exs config/
COPY server/config/prod.exs server/config/can.exs server/config/stag.exs config/

# Copy path dependency sources for compilation
COPY xcode_processor/lib /xcode_processor/lib

RUN mix deps.compile

# ========================================
# Stage: OG image generator
# Renders marketing/docs Open Graph images via headless Chromium. Built in
# parallel with the main builder (both branch from deps-builder) so its long
# Chromium-driven runtime overlaps with mix compile + release rather than
# stacking on top of them.
# ========================================
FROM deps-builder AS og-images

# Chromium and font packages only this stage needs. Sits before the source
# COPY so the apt layer stays cached as long as deps-builder is cached, even
# when server/lib changes.
RUN apt-get update -y && \
  apt-get install -y --no-install-recommends chromium fonts-noto-cjk fonts-noto-core && \
  apt-get clean && rm -rf /var/lib/apt/lists/*

COPY server/priv priv
COPY skills/skills priv/static/skills
COPY examples/xcode /examples/xcode
COPY server/lib lib

RUN mix compile

# Persist generated OG images (and their .cachekey sidecars) across builds in
# BuildKit caches. The mix tasks skip per-image rendering when the input hash
# matches the existing sidecar, so when the layer above is invalidated by an
# unrelated lib change we still get a fast no-op pass for unchanged images.
RUN --mount=type=cache,id=og-marketing,target=/og-cache/marketing,sharing=locked \
    --mount=type=cache,id=og-docs,target=/og-cache/docs,sharing=locked \
    set -e; \
    OUT_M=/app/_build/${MIX_ENV}/lib/tuist/priv/static/marketing/images/og/generated; \
    OUT_D=/app/_build/${MIX_ENV}/lib/tuist/priv/docs/images/og/generated; \
    mkdir -p "$OUT_M" "$OUT_D"; \
    if [ -d /og-cache/marketing ] && [ -n "$(ls -A /og-cache/marketing 2>/dev/null)" ]; then \
      cp -a /og-cache/marketing/. "$OUT_M/"; \
    fi; \
    if [ -d /og-cache/docs ] && [ -n "$(ls -A /og-cache/docs 2>/dev/null)" ]; then \
      cp -a /og-cache/docs/. "$OUT_D/"; \
    fi; \
    mix docs.gen.og_images; \
    mix marketing.gen.og_images; \
    cp -a "$OUT_M/." /og-cache/marketing/; \
    cp -a "$OUT_D/." /og-cache/docs/

# ========================================
# Stage 3: Main application builder
# ========================================
FROM deps-builder AS builder

COPY server/priv priv
COPY skills/skills priv/static/skills
COPY server/assets assets
COPY server/native native

# Xcode example READMEs needed at compile time by Tuist.Docs.Loader
COPY examples/xcode /examples/xcode

COPY server/lib lib

RUN mix compile --warnings-as-errors

COPY server/config/runtime.exs config/
COPY server/rel rel

COPY --from=npm-deps /app/node_modules /app/node_modules
COPY --from=npm-deps /noora/priv/static /noora/priv/static
RUN mix assets.deploy

# Pull pre-generated OG images from the parallel og-images stage. Splitting
# the Chromium pipeline into its own stage lets it run concurrently with mix
# compile + assets.deploy + release here instead of stacking on top.
COPY --from=og-images /app/_build/${MIX_ENV}/lib/tuist/priv/static/marketing/images/og/generated /app/_build/${MIX_ENV}/lib/tuist/priv/static/marketing/images/og/generated
COPY --from=og-images /app/_build/${MIX_ENV}/lib/tuist/priv/docs/images/og/generated /app/_build/${MIX_ENV}/lib/tuist/priv/docs/images/og/generated

RUN mix release

# ========================================
# Stage: NIF bridge builder
# Compiles the C NIF bridge linking against the Swift library and places the
# result under the release's tuist app priv dir so Tuist.Processor.XCActivityLogNIF
# can load it at runtime.
# ========================================
FROM builder AS nif-bridge-builder

COPY server/native/xcactivitylog_nif/nif_bridge.c /tmp/nif/nif_bridge.c
COPY --from=swift-builder /nif/libXCActivityLogNIF.so /tmp/nif/libXCActivityLogNIF.so

RUN TUIST_REL_DIR=$(ls -d /app/_build/${MIX_ENV}/rel/tuist/lib/tuist-*) && \
    mkdir -p "$TUIST_REL_DIR/priv/native" && \
    ERL_INCLUDE=$(erl -eval 'io:format("~s/erts-~s/include", [code:root_dir(), erlang:system_info(version)])' -s init stop -noshell) && \
    cc -shared -fPIC \
      -o "$TUIST_REL_DIR/priv/native/xcactivitylog_nif.so" \
      /tmp/nif/nif_bridge.c \
      -I"$ERL_INCLUDE" \
      -L/tmp/nif \
      -lXCActivityLogNIF \
      -Wl,-rpath,'$ORIGIN' && \
    cp /tmp/nif/libXCActivityLogNIF.so "$TUIST_REL_DIR/priv/native/"

# ========================================
# Stage: Common runtime
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
ARG TUIST_VERSION=0.0.0
ARG EMBED_CLICKHOUSE=false
ENV MIX_ENV=$MIX_ENV
ENV TUIST_HOSTED=$TUIST_HOSTED
ENV TUIST_VERSION=$TUIST_VERSION

# Swift runtime libs the NIF links against at load time. Small (~20 MB) but
# carried by every release image because any pod may run in processor mode
# (TUIST_PROCESSOR_MODE=true) and execute the xcactivitylog NIF.
COPY --from=swift-builder /nif/swift-libs/ /usr/local/lib/
RUN ldconfig

# Release taken from nif-bridge-builder so the compiled xcactivitylog_nif +
# libXCActivityLogNIF are already under lib/tuist-<vsn>/priv/native where
# Tuist.Processor.XCActivityLogNIF.load_nif expects them.
COPY --from=nif-bridge-builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/tuist ./

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
# Stage: Default runtime
# Boots as web server by default; set TUIST_PROCESSOR_MODE=true to run as an
# Oban processor pod (queue consumer, no web endpoint). The Swift NIF ships
# in runner-base, so no extra overlay is required for either role.
# ========================================
FROM runner-base AS runner

USER nobody

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8080/ready || exit 1

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["sh", "-c", "/app/bin/start"]
