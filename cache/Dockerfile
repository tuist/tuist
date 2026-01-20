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

COPY cache/mix.exs cache/mix.lock ./

# Copy tuist_common for path dependency
COPY tuist_common /tuist_common

RUN mix deps.get --only $MIX_ENV
RUN mkdir config

COPY cache/config/config.exs cache/config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY cache/lib lib

RUN mix compile

COPY cache/config/runtime.exs config/

COPY cache/rel rel
COPY cache/priv priv
RUN mix release

FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
	apt-get install -y libstdc++6 openssl locales ca-certificates \
	&& apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

RUN groupadd -g 990 cache && useradd -u 990 -g cache cache

WORKDIR "/app"

ENV MIX_ENV="prod"

COPY --from=builder --chown=cache:cache /app/_build/${MIX_ENV}/rel/cache ./

USER cache

CMD ["/app/bin/server"]
