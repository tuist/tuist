ARG ELIXIR_VERSION=1.20.5
ARG OTP_VERSION=29.1.3
ARG DEBIAN_VERSION=trixie-20261123-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM scratch AS certificate-trust
COPY infra/certificate-trust/pem-store.sh infra/certificate-trust/policy.json /

# The GPUI web edge served under /app: Luft's luft-gpui-web crate compiled to
# wasm with Luft's pinned Rust (luft/mise.toml) and bound for the browser.
# Single-threaded, so it builds on stable Rust and needs no cross-origin
# isolation. Its SQLite compiles with clang.
FROM rust:1.98.1-slim-trixie AS luft-web

RUN apt-get update -y && apt-get install -y clang llvm ca-certificates \
    && sed -i -e 's|^mozilla/emSign_ECC_Root_CA_-_G3.crt|!&|' -e 's|^mozilla/Comodo_AAA_Services_root.crt|!&|' /etc/ca-certificates.conf \
    && update-ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*
RUN --mount=type=bind,from=certificate-trust,target=/certificate-trust bash /certificate-trust/pem-store.sh check /etc/ssl/certs/ca-certificates.crt

# Must match the wasm-bindgen crate in luft/Cargo.lock.
RUN rustup target add wasm32-unknown-unknown \
    && cargo install --locked wasm-bindgen-cli --version 0.2.130

WORKDIR /luft
COPY luft ./
RUN cargo build --locked --release --target wasm32-unknown-unknown -p luft-gpui-web \
    && wasm-bindgen --target web --no-typescript --out-dir /out target/wasm32-unknown-unknown/release/luft_gpui_web.wasm \
    && cp gpui-web/index.html gpui-web/main.js /out/ \
    && gzip -9 -k /out/luft_gpui_web_bg.wasm /out/luft_gpui_web.js

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && apt-get install -y build-essential git curl ca-certificates \
    && sed -i -e 's|^mozilla/emSign_ECC_Root_CA_-_G3.crt|!&|' -e 's|^mozilla/Comodo_AAA_Services_root.crt|!&|' /etc/ca-certificates.conf \
    && update-ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*
RUN --mount=type=bind,from=certificate-trust,target=/certificate-trust bash /certificate-trust/pem-store.sh check /etc/ssl/certs/ca-certificates.crt

# Match the native SDK's NSH version. Only this checksum-verified compiler
# ships alongside the release.
ARG TARGETARCH
RUN set -eu; \
    case "$TARGETARCH" in \
      amd64) asset=nsh-linux-x86_64.tar.gz; sha=f34729e613196ca122d956deb543a92f319e053ff17dfc09ba04a6ec2fb79c74 ;; \
      arm64) asset=nsh-linux-arm64.tar.gz; sha=6f182e61ce68115b99d29a096f4a935bf3e7aa2733cdf9f135274ccec00dfef6 ;; \
      *) echo "NSH has no Linux release for $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/longbridge/nsh/releases/download/v0.5.1/$asset" -o /tmp/nsh.tar.gz; \
    echo "$sha  /tmp/nsh.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/nsh.tar.gz -C /tmp nsh/bin/nsh; \
    mv /tmp/nsh/bin/nsh /usr/local/bin/nsh; \
    rm -rf /tmp/nsh /tmp/nsh.tar.gz; \
    nsh --version

ENV HEX_CACERTS_PATH=/etc/ssl/certs/ca-certificates.crt
WORKDIR /app/luft-server

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV="prod"

# Threads use remote sandboxes and runners, not Condukt's optional local NIF backends.
ENV CONDUKT_MICROSANDBOX_DISABLE=1 CONDUKT_BASHKIT_DISABLE=1

# tuist_ex is dev/test-only; Condukt is part of the production runtime.
COPY luft-server/mix.exs luft-server/mix.lock ./
COPY condukt/mix.exs /app/condukt/mix.exs
RUN mkdir config
COPY luft-server/config/config.exs luft-server/config/${MIX_ENV}.exs config/
RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile --skip-local-deps

# Only migrations, the trusted native card kit and the GPUI web edge under
# /app; never a frontend shell at the root.
COPY condukt/lib /app/condukt/lib
COPY condukt/priv /app/condukt/priv
COPY luft-server/priv/repo priv/repo
COPY luft-server/priv/threads priv/threads
COPY luft-server/lib lib
COPY --from=luft-web /out priv/static/app
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
COPY --from=builder /usr/local/bin/nsh /usr/local/bin/nsh
COPY --from=builder --chown=nobody:root /app/luft-server/_build/${MIX_ENV}/rel/luft_server ./
USER nobody

CMD ["/app/bin/server"]
