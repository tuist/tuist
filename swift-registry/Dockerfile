ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28.4.3
ARG DEBIAN_VERSION=trixie-20260406-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && apt-get install -y build-essential git zip \
	&& apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

RUN mix local.hex --force && \
	mix local.rebar --force

ENV MIX_ENV="prod"

COPY swift-registry/mix.exs swift-registry/mix.lock ./

# Copy tuist_common for path dependency
COPY tuist_common /tuist_common

RUN mix deps.get --only $MIX_ENV
RUN mkdir config

COPY swift-registry/config/config.exs swift-registry/config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY swift-registry/lib lib

RUN mix compile

COPY swift-registry/config/runtime.exs config/

COPY swift-registry/rel rel
COPY swift-registry/priv priv
RUN mix release

FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
	apt-get install -y libstdc++6 openssl locales ca-certificates curl git zip unzip \
	&& apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

RUN groupadd -g 990 swift_registry && useradd -u 990 -g swift_registry swift_registry

WORKDIR "/app"

ENV MIX_ENV="prod"

COPY --from=builder --chown=swift_registry:swift_registry /app/_build/${MIX_ENV}/rel/swift_registry ./

USER swift_registry

CMD ["/app/bin/swift_registry", "start"]
