ARG ELIXIR_VERSION=1.20.2
ARG OTP_VERSION=29.0.3
ARG DEBIAN_VERSION=trixie-20260623-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app/tuist-ops

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV="prod"

COPY tuist-ops/mix.exs tuist-ops/mix.lock ./
RUN mkdir config

COPY tuist-ops/config/config.exs tuist-ops/config/${MIX_ENV}.exs config/

RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

COPY tuist-ops/priv priv
COPY tuist-ops/lib lib
COPY tuist-ops/assets assets

RUN mix compile --warnings-as-errors

# Bundle the operator UI. esbuild resolves Noora from the Hex package's
# prebuilt priv/static/noora.js (no node/npm), and downloads its own
# standalone binary on first run.
RUN mix assets.deploy

COPY tuist-ops/config/runtime.exs config/

COPY tuist-ops/rel rel
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

COPY --from=builder --chown=nobody:root /app/tuist-ops/_build/${MIX_ENV}/rel/tuist_ops ./

USER nobody

CMD ["/app/bin/server"]
