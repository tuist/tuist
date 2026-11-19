ARG ELIXIR_VERSION=1.20.2
ARG OTP_VERSION=29.0.3
ARG DEBIAN_VERSION=trixie-20260623-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM scratch AS certificate-trust
COPY infra/certificate-trust/pem-store.sh infra/certificate-trust/policy.json /

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && apt-get install -y build-essential git ca-certificates \
    && sed -i -e 's|^mozilla/emSign_ECC_Root_CA_-_G3.crt|!&|' -e 's|^mozilla/Comodo_AAA_Services_root.crt|!&|' /etc/ca-certificates.conf \
    && update-ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*
RUN --mount=type=bind,from=certificate-trust,target=/certificate-trust bash /certificate-trust/pem-store.sh check /etc/ssl/certs/ca-certificates.crt

ENV HEX_CACERTS_PATH=/etc/ssl/certs/ca-certificates.crt
WORKDIR /app/luft-server

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV="prod"

# tuist_ex is a dev/test-only path dependency, so production needs no sibling checkout.
COPY luft-server/mix.exs luft-server/mix.lock ./
RUN mkdir config
COPY luft-server/config/config.exs luft-server/config/${MIX_ENV}.exs config/
RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

# Only migrations: a local priv/static (gitignored) must not leak into the image.
COPY luft-server/priv/repo priv/repo
# The Luft web app, which Struo builds (`struo build LuftWeb` in luft/) and the
# build passes as the `site` context:
# --build-context site=luft/.struo/out/LuftWeb/dist
COPY --from=site . priv/static/
# Precompressed copies for Plug.Static's `gzip: true`; the core's wasm shrinks
# from about 4.8 MB to 2 MB.
RUN find priv/static/assets -type f \( -name '*.wasm' -o -name '*.js' -o -name '*.css' \) -exec gzip -9k {} +
COPY luft-server/lib lib
RUN mix compile --warnings-as-errors

COPY luft-server/config/runtime.exs config/
COPY luft-server/rel rel
RUN mix release

FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl locales ca-certificates \
    && sed -i -e 's|^mozilla/emSign_ECC_Root_CA_-_G3.crt|!&|' -e 's|^mozilla/Comodo_AAA_Services_root.crt|!&|' /etc/ca-certificates.conf \
    && update-ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*
RUN --mount=type=bind,from=certificate-trust,target=/certificate-trust bash /certificate-trust/pem-store.sh check /etc/ssl/certs/ca-certificates.crt

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app
ENV MIX_ENV="prod"
COPY --from=builder --chown=nobody:root /app/luft-server/_build/${MIX_ENV}/rel/luft_server ./
USER nobody

CMD ["/app/bin/server"]
