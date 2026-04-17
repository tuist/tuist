ARG ELIXIR_VERSION=1.19.1
ARG OTP_VERSION=28.1.1
ARG DEBIAN_VERSION=trixie-20251020-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM node:24-slim AS npm-deps
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable

COPY noora/package.json /app/noora/
COPY noora/js/ /app/noora/js/
COPY noora/css/ /app/noora/css/
COPY noora/lib/ /app/noora/lib/
COPY noora/mix.exs noora/README.md /app/noora/

WORKDIR /app/noora
RUN pnpm install
RUN mkdir -p priv/static
RUN pnpm run build

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app/slack

RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV="prod"

COPY slack/mix.exs slack/mix.lock ./
RUN mkdir config

COPY slack/config/config.exs slack/config/${MIX_ENV}.exs config/

COPY --from=npm-deps /app/noora /app/noora

RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

COPY slack/priv priv
COPY slack/lib lib
COPY slack/assets assets

RUN mix assets.deploy

RUN mix compile --warnings-as-errors

COPY slack/config/runtime.exs config/

COPY slack/rel rel
RUN mix release

FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl locales ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

ENV MIX_ENV="prod"

COPY --from=builder --chown=nobody:root /app/slack/_build/${MIX_ENV}/rel/slack ./

USER nobody

CMD ["/app/bin/server"]
