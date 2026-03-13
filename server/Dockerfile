ARG ELIXIR_VERSION=1.19.1
ARG OTP_VERSION=28.1
ARG DEBIAN_VERSION=bookworm-20251020-slim
ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
# For preview environments, override with ghcr.io/tuist/tuist-preview-base:latest
# to skip system package and ClickHouse installation (~7 min savings).
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

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

COPY server/mix.exs server/mix.lock ./
RUN mkdir config

# Copy path dependencies
COPY tuist_common /tuist_common
COPY noora /noora

RUN mix deps.get --only $MIX_ENV

# Config files must be present before compiling dependencies
COPY server/config/config.exs server/config/${MIX_ENV}.exs config/

RUN mix deps.compile

# ========================================
# Stage 3: Main application builder
# ========================================
FROM deps-builder AS builder

COPY server/priv priv
COPY skills/skills priv/static/skills
COPY server/assets assets

COPY server/lib lib

RUN mix compile --warnings-as-errors

COPY server/config/runtime.exs config/
COPY server/rel rel

COPY --from=npm-deps /app/node_modules /app/node_modules
COPY --from=npm-deps /noora/priv/static /noora/priv/static
RUN mix assets.deploy

RUN mix release

# ========================================
# Stage 4: Final runtime image
# ========================================
# When RUNNER_IMAGE is the preview base (ghcr.io/tuist/tuist-preview-base:latest),
# system packages, locale, and ClickHouse are already installed — the conditional
# RUN steps below become no-ops, saving ~7 minutes on preview builds.
FROM ${RUNNER_IMAGE}

ARG PREBUILT_RUNNER=false
ARG EMBED_CLICKHOUSE=false

RUN if [ "$PREBUILT_RUNNER" = "false" ]; then \
  apt-get update -y && \
  apt-get upgrade -y && \
  apt-get install -y curl build-essential gcc wget libvips libstdc++6 openssl libncurses5 locales ca-certificates postgresql-client zip unzip git \
  && apt-get clean && rm -f /var/lib/apt/lists/*_* && \
  sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen; \
  fi

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

ARG MIX_ENV=prod
ARG TUIST_HOSTED=1
ENV MIX_ENV=$MIX_ENV
ENV TUIST_HOSTED=$TUIST_HOSTED

COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/tuist ./

COPY server/priv/secrets/can.yml.enc /app/priv/secrets/can.yml.enc
COPY server/priv/secrets/stag.yml.enc /app/priv/secrets/stag.yml.enc
COPY server/priv/secrets/prod.yml.enc /app/priv/secrets/prod.yml.enc

# For non-hosted builds (previews/self-hosted): remove encrypted secrets
RUN if [ "$TUIST_HOSTED" = "0" ]; then \
  rm -rf /app/priv/secrets/can.yml.enc; \
  rm -rf /app/priv/secrets/stag.yml.enc; \
  rm -rf /app/priv/secrets/prod.yml.enc; \
  fi

# Install ClickHouse only when not using the prebuilt runner (which has it already).
RUN if [ "$PREBUILT_RUNNER" = "false" ] && [ "$EMBED_CLICKHOUSE" = "true" ]; then \
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
RUN if [ "$EMBED_CLICKHOUSE" = "true" ] || [ "$PREBUILT_RUNNER" = "true" ]; then \
  cp /tmp/clickhouse-preview-config.xml /etc/clickhouse-server/config.d/preview.xml; \
  fi && rm -f /tmp/clickhouse-preview-config.xml

ENV SECRETS_DIRECTORY=/app/priv/secrets/
COPY server/priv/repo/structure.sql /app/priv/repo/structure.sql

USER nobody

CMD ["sh", "-c", "/app/bin/start"]
