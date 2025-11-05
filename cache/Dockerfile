ARG ELIXIR_VERSION=1.19.2
ARG OTP_VERSION=28.1
ARG DEBIAN_VERSION=trixie-20251020-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && apt-get install -y build-essential git \
	&& apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

RUN mix local.hex --force && \
	mix local.rebar --force

ENV MIX_ENV="prod"

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY lib lib

RUN mix compile

COPY config/runtime.exs config/

COPY rel rel
COPY priv priv
RUN mix release

FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
	apt-get install -y libstdc++6 openssl locales ca-certificates \
	&& apt-get clean && rm -f /var/lib/apt/lists/*_*

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

RUN mkdir -p /data && chown nobody:nogroup /data

ENV MIX_ENV="prod"

COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/cache ./

USER nobody

CMD ["/app/bin/server"]
