# Find eligible builder and runner images on Docker Hub. We use Ubuntu/Debian
# instead of Alpine to avoid DNS issues that arise often.
#
# Build context is the monorepo root: atlas depends on `../noora` as a
# local path dependency, so both `atlas/` and `noora/` need to be
# available inside the builder image. All COPY sources are therefore
# repo-relative (e.g. `atlas/mix.exs`, `noora`).
ARG ELIXIR_VERSION=1.20.2
ARG OTP_VERSION=29.0.3
# hexpm/elixir uses date-pinned tags. bookworm-20260623-slim is the
# combination that has a published image for the pinned Elixir/OTP.
# The runner base needs to be a real debian tag that also exists on
# Docker Hub for the same architecture; bookworm-slim covers that.
ARG DEBIAN_BUILDER_VERSION=bookworm-20260623-slim
ARG DEBIAN_RUNNER_VERSION=bookworm-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_BUILDER_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_RUNNER_VERSION}"

# ========================================
# Stage: noora asset builder
# Builds noora's CSS/JS from source so Atlas can embed the digested output
# in the runtime image. Kept in a separate stage so the Elixir builder
# doesn't need Node/aube in its layer.
# ========================================
FROM node:22-slim AS noora-assets

ENV CI=1
ENV XDG_DATA_HOME="/aube-data"

RUN npm install -g --ignore-scripts=false @endevco/aube@1.41.0

COPY noora /noora
WORKDIR /noora
RUN --mount=type=cache,id=aube,target=/aube-data/aube aube install
RUN aube run build

# ========================================
# Stage: Elixir builder
# ========================================
FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV="prod"

# Copy the path-dependency source before running mix deps.get so mix can
# resolve `{:noora, path: "../noora"}`. The aube-built priv/static from
# the noora-assets stage overlays on top so Atlas can serve noora's
# compiled CSS/JS.
COPY noora /noora
COPY --from=noora-assets /noora/priv/static /noora/priv/static

# install mix dependencies
COPY atlas/mix.exs atlas/mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY atlas/config/config.exs atlas/config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY atlas/priv priv
COPY atlas/lib lib
COPY atlas/assets assets

# Compile the project (generates colocated hooks needed by esbuild)
RUN mix compile

# compile assets
RUN mix assets.deploy

# Changes to config/runtime.exs don't require recompiling the code
COPY atlas/config/runtime.exs config/

COPY atlas/rel rel
RUN mix release

# ========================================
# Stage: Runner
# ========================================
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
  apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates poppler-utils pandoc chromium fonts-liberation \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Chromium binary path used by browse_chrome to start headless instances for
# the `browse_url` MCP tool. Set here so the pool boots automatically.
# HOME must be writable for chromium's crashpad child; the `nobody` user
# has no real home directory, so point it at /tmp.
ENV CHROME_PATH=/usr/bin/chromium
ENV HOME=/tmp

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/atlas ./

USER nobody

# If using an environment that doesn't automatically reap orphaned child
# processes, it is advised to add an init process such as tini via
# temporary `apt-get install tini` in the runner stage, and adding an
# pointpoint. See https://github.com/krallin/tini for details
# ENTRYPOINT ["/tini", "--"]

CMD ["/app/bin/server"]
