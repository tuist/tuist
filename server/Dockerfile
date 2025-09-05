# Find eligible builder and runner images on Docker Hub. We use Ubuntu/Debian
# instead of Alpine to avoid DNS resolution issues in production.
#
# https://hub.docker.com/r/hexpm/elixir/tags?page=1&name=ubuntu
# https://hub.docker.com/_/ubuntu?tab=tags
#
# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the build image
#   - https://hub.docker.com/_/debian?tab=tags&page=1&name=bullseye-20231009-slim - for the release image
#   - https://pkgs.org/ - resource for finding needed packages
#   - Ex: hexpm/elixir:1.16.0-erlang-26.2.1-debian-bullseye-20231009-slim
#

ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=27.3.2
ARG DEBIAN_VERSION=bookworm-20250407-slim
ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

# install NPM dependencies
FROM node:22-slim AS npm-deps
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable
COPY package.json /app/package.json
COPY pnpm-lock.yaml /app/pnpm-lock.yaml
WORKDIR /app
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile

FROM ${BUILDER_IMAGE} AS builder

# install build dependencies
RUN apt-get update -y && apt-get upgrade -y && apt-get install -y build-essential git xz-utils p7zip-full wget \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

# install zig manually since it's not available via apt-get
RUN wget -q https://ziglang.org/download/0.14.1/zig-x86_64-linux-0.14.1.tar.xz \
  && tar -xf zig-x86_64-linux-0.14.1.tar.xz \
  && mv zig-x86_64-linux-0.14.1 /usr/local/zig \
  && ln -s /usr/local/zig/zig /usr/local/bin/zig \
  && rm zig-x86_64-linux-0.14.1.tar.xz

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
  mix local.rebar --force

# set build ENV
ARG MIX_ENV=prod
ENV MIX_ENV=$MIX_ENV
ARG TUIST_HOSTED=1
ENV TUIST_HOSTED=$TUIST_HOSTED

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Copy runner source before building
COPY runner runner

# Build runner binary
WORKDIR /app/runner
RUN mix deps.get --only $MIX_ENV
RUN MIX_ENV=prod mix release runner
RUN mkdir -p /app/build
RUN cp burrito_out/runner_macos /app/build/runner

WORKDIR /app

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
COPY assets assets
COPY lib lib

# compile assets
COPY --from=npm-deps /app/node_modules /app/node_modules
RUN mix assets.deploy

# generate og images
RUN mix marketing.gen.og_images;

# Compile the release

RUN mix compile --warnings-as-errors

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
  apt-get upgrade -y && \
  apt-get install -y curl build-essential gcc wget libvips libstdc++6 openssl libncurses5 locales ca-certificates postgresql-client zip unzip \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# set runner ENV
ARG MIX_ENV=prod
ARG APP_REVISION
ARG TUIST_HOSTED=1
ARG TUIST_VERSION
ENV MIX_ENV=$MIX_ENV
ENV TUIST_VERSION=$TUIST_VERSION
ENV APP_REVISION=$APP_REVISION
ENV TUIST_HOSTED=$TUIST_HOSTED

# We copy the encrypted secrets
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/tuist ./
COPY priv/secrets/can.yml.enc /app/priv/secrets/can.yml.enc
COPY priv/secrets/stag.yml.enc /app/priv/secrets/stag.yml.enc
COPY priv/secrets/prod.yml.enc /app/priv/secrets/prod.yml.enc

# Delete the content that's not needed for the on-premise version
RUN if [ "$TUIST_HOSTED" = "0" ]; then \
  echo "TUIST_HOSTED is set to 0, executing specific commands"; \
  rm -rf /app/priv/secrets/can.yml.enc; \
  rm -rf /app/priv/secrets/stag.yml.enc; \
  rm -rf /app/priv/secrets/prod.yml.enc; \
  fi

ENV SECRETS_DIRECTORY=/app/priv/secrets/
COPY priv/repo/structure.sql /app/priv/repo/structure.sql

COPY --from=builder /app/build/runner /app/bin/runner

USER nobody

# If using an environment that doesn't automatically reap zombie processes, it is
# advised to add an init process such as tini via `apt-get install`
# above and adding an entrypoint. See https://github.com/krallin/tini for details
# ENTRYPOINT ["/tini", "--"]

CMD ["sh", "-c", "/app/bin/start"]
