ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=27.3.4.2
ARG DEBIAN_VERSION=bookworm-20250811-slim
ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

# ========================================
# Stage 1: NPM dependencies
# ========================================
FROM node:22-slim AS npm-deps
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable
COPY package.json /app/package.json
COPY pnpm-lock.yaml /app/pnpm-lock.yaml
WORKDIR /app
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile

# ========================================
# Stage 2: Base dependencies builder
# Compiles all dependencies including runner as a dependency
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

COPY mix.exs mix.lock ./
RUN mkdir config

# Only runner's mix.exs needed for deps.get to work
COPY runner/mix.exs runner/mix.exs

RUN mix deps.get --only $MIX_ENV

# Config files must be present before compiling dependencies
COPY config/config.exs config/${MIX_ENV}.exs config/

# Minimal runner source needed for compilation
COPY runner/lib runner/lib

RUN mix deps.compile

# ========================================
# Stage 3: Runner binary builder
# Builds the runner binary using compiled deps from deps-builder
# ========================================
FROM ${BUILDER_IMAGE} AS runner-binary-builder

RUN apt-get update -y && apt-get upgrade -y && apt-get install -y build-essential git xz-utils p7zip-full wget \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Zig is not available via apt-get
RUN wget -q https://ziglang.org/download/0.14.1/zig-x86_64-linux-0.14.1.tar.xz \
  && tar -xf zig-x86_64-linux-0.14.1.tar.xz \
  && mv zig-x86_64-linux-0.14.1 /usr/local/zig \
  && ln -s /usr/local/zig/zig /usr/local/bin/zig \
  && rm zig-x86_64-linux-0.14.1.tar.xz

WORKDIR /app

RUN mix local.hex --force && \
  mix local.rebar --force

ARG MIX_ENV=prod
ENV MIX_ENV=$MIX_ENV
ARG TUIST_HOSTED=1
ENV TUIST_HOSTED=$TUIST_HOSTED

# Reuse compiled dependencies from deps-builder
COPY --from=deps-builder /app/mix.* ./
COPY --from=deps-builder /app/deps deps
COPY --from=deps-builder /app/_build _build
COPY --from=deps-builder /app/config config

COPY runner runner

WORKDIR /app/runner
RUN mix deps.get --only $MIX_ENV
RUN MIX_ENV=prod mix release runner
RUN mkdir -p /app/build && cp burrito_out/runner_macos /app/build/runner

# ========================================
# Stage 4: Main application builder
# ========================================
FROM deps-builder AS builder

COPY priv priv
COPY assets assets

COPY lib lib

RUN mix compile --warnings-as-errors

COPY config/runtime.exs config/
COPY rel rel

RUN mix release

COPY --from=npm-deps /app/node_modules /app/node_modules
RUN mix assets.deploy

# ========================================
# Stage 5: Final runtime image
# ========================================
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
  apt-get upgrade -y && \
  apt-get install -y curl build-essential gcc wget libvips libstdc++6 openssl libncurses5 locales ca-certificates postgresql-client zip unzip \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

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

COPY priv/secrets/can.yml.enc /app/priv/secrets/can.yml.enc
COPY priv/secrets/stag.yml.enc /app/priv/secrets/stag.yml.enc
COPY priv/secrets/prod.yml.enc /app/priv/secrets/prod.yml.enc

# Remove hosted-only secrets for on-premise builds
RUN if [ "$TUIST_HOSTED" = "0" ]; then \
  echo "TUIST_HOSTED is set to 0, executing specific commands"; \
  rm -rf /app/priv/secrets/can.yml.enc; \
  rm -rf /app/priv/secrets/stag.yml.enc; \
  rm -rf /app/priv/secrets/prod.yml.enc; \
  fi

ENV SECRETS_DIRECTORY=/app/priv/secrets/
COPY priv/repo/structure.sql /app/priv/repo/structure.sql

COPY --from=runner-binary-builder /app/build/runner /app/bin/runner

USER nobody

CMD ["sh", "-c", "/app/bin/start"]
