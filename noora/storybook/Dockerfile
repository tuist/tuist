# Find eligible builder and runner images on Docker Hub. We use Ubuntu/Debian
# instead of Alpine to avoid DNS resolution issues in production.
#
# https://hub.docker.com/r/hexpm/elixir/tags?page=1&name=ubuntu
# https://hub.docker.com/_/ubuntu?tab=tags
#
# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the build image
#   - https://hub.docker.com/_/debian?tab=tags&page=1&name=bullseye-20250407-slim - for the release image
#   - https://pkgs.org/ - resource for finding needed packages
#   - Ex: hexpm/elixir:1.18.3-erlang-27.3.2-debian-bullseye-20250407-slim
#
ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28.4.3
ARG DEBIAN_VERSION=bullseye-20260406-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM node:24-slim AS npm-deps
ENV XDG_DATA_HOME="/aube-data"
RUN npm install -g --ignore-scripts=false @endevco/aube

COPY package.json /app/noora/
COPY js/ /app/noora/js/
COPY css/ /app/noora/css/
COPY lib/ /app/noora/lib/
COPY mix.exs README.md /app/noora/

WORKDIR /app/noora
RUN aube install

RUN mkdir -p priv/static
RUN aube run build
RUN ./node_modules/.bin/esbuild css/noora.css --bundle --minify --outfile=./priv/static/noora.css

FROM ${BUILDER_IMAGE} AS builder

# install build dependencies
RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# prepare build dir - mirror local layout: noora at /app, storybook at /app/storybook
WORKDIR /app/storybook

# install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

COPY storybook/mix.exs storybook/mix.lock ./
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY storybook/config/config.exs storybook/config/${MIX_ENV}.exs config/

# Copy pre-built noora assets from npm-deps stage (path: ".." resolves to /app)
COPY --from=npm-deps /app/noora /app

RUN mix deps.get --only $MIX_ENV

RUN mix deps.compile

COPY storybook/priv priv

COPY storybook/lib lib

COPY storybook/storybook storybook

COPY storybook/assets assets

RUN mix assets.deploy

# Compile the release
RUN mix compile

# Changes to config/runtime.exs don't require recompiling the code
COPY storybook/config/runtime.exs config/

COPY storybook/rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/storybook/_build/${MIX_ENV}/rel/noora_storybook ./

USER nobody

CMD ["/app/bin/server"]
