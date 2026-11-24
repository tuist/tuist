# Build context is `symptoms/`, with the certificate trust policy as the named
# context `certificate-trust`:
#
#   docker build --build-context certificate-trust=infra/certificate-trust \
#     -f symptoms/Dockerfile symptoms
#
# The builder and runner match tuist-ops and the Elixir and Erlang versions in
# symptoms/mise.toml.
ARG ELIXIR_VERSION=1.20.2
ARG OTP_VERSION=29.0.3
ARG DEBIAN_VERSION=trixie-20260623-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && apt-get install -y build-essential git ca-certificates \
    && sed -i -e 's|^mozilla/emSign_ECC_Root_CA_-_G3.crt|!&|' -e 's|^mozilla/Comodo_AAA_Services_root.crt|!&|' /etc/ca-certificates.conf \
    && update-ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*
RUN --mount=type=bind,from=certificate-trust,target=/certificate-trust bash /certificate-trust/pem-store.sh check /etc/ssl/certs/ca-certificates.crt

ENV HEX_CACERTS_PATH=/etc/ssl/certs/ca-certificates.crt
ENV REBAR_OFFLINE=1
WORKDIR /app/symptoms

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV="prod"

COPY mix.exs mix.lock ./
RUN mkdir config

COPY config/config.exs config/${MIX_ENV}.exs config/

RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

# Migrations live in priv/repo/migrations, which the release runs on boot.
# Copied through a bind mount so a tree without priv/ still builds.
RUN --mount=type=bind,target=/src if [ -d /src/priv ]; then cp -R /src/priv priv; fi
COPY lib lib

RUN mix compile --warnings-as-errors

COPY config/runtime.exs config/

COPY rel rel
RUN mix release

FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl locales ca-certificates \
    && sed -i -e 's|^mozilla/emSign_ECC_Root_CA_-_G3.crt|!&|' -e 's|^mozilla/Comodo_AAA_Services_root.crt|!&|' /etc/ca-certificates.conf \
    && update-ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*
RUN --mount=type=bind,from=certificate-trust,target=/certificate-trust bash /certificate-trust/pem-store.sh check /etc/ssl/certs/ca-certificates.crt

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

ENV MIX_ENV="prod"

COPY --from=builder --chown=nobody:root /app/symptoms/_build/${MIX_ENV}/rel/symptoms ./

USER nobody

CMD ["/app/bin/server"]
