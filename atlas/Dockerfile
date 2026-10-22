# Find eligible builder and runner images on Docker Hub. We use Ubuntu/Debian
# instead of Alpine to avoid DNS issues that arise often.
#
# Build context is the monorepo root: atlas depends on `../noora` as a
# local path dependency, so both `atlas/` and `noora/` need to be
# available inside the builder image. All COPY sources are therefore
# repo-relative (e.g. `atlas/mix.exs`, `noora`).
# The builder matches the Elixir and Erlang versions in the root mise.toml.
# hexpm/elixir uses date-pinned tags; bookworm-20260623-slim is the
# combination that has a published image for that Elixir/OTP pair.
# The Condukt native dependency needs GNU C Library 2.38 or newer, so the
# runner uses Debian Trixie.
#
# Base images are pinned by digest so Once can cache individual instructions
# in CI without a moving tag serving a stale image. A reference with both a
# tag and a digest is pulled by the digest alone, so each image is written
# out as one literal and its tag and digest change in the same edit.
ARG BUILDER_IMAGE=hexpm/elixir:1.20.2-erlang-29.0.3-debian-bookworm-20260623-slim@sha256:4ced3cb72e20ff8ad8315ec05af520c43431ea2ae459a205f5217670df45f2cf
ARG RUNNER_IMAGE=debian:trixie-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f

# Aube embeds WebPKI roots; Node's CA settings cannot patch its native binary.
FROM rust:1.94-bookworm@sha256:6ae102bdbf528294bc79ad6e1fae682f6f7c2a6e6621506ba959f9685b308a55 AS aube-builder
COPY infra/certificate-trust/pem-store.sh infra/certificate-trust/policy.json /opt/tuist/certificate-trust/
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates cmake \
    && sed -i -e 's|^mozilla/emSign_ECC_Root_CA_-_G3.crt|!&|' -e 's|^mozilla/Comodo_AAA_Services_root.crt|!&|' /etc/ca-certificates.conf \
    && update-ca-certificates && rm -rf /var/lib/apt/lists/*
RUN bash /opt/tuist/certificate-trust/pem-store.sh check /etc/ssl/certs/ca-certificates.crt
WORKDIR /aube
RUN git init . && git remote add origin https://github.com/endevco/aube.git \
    && git fetch --depth 1 origin e7b898917c43ba72da002d12f2588f7bfa7e6890 \
    && git checkout --detach FETCH_HEAD \
    && cargo update -p rustls-webpki --precise 0.103.16 \
    && cargo update -p webpki-roots --precise 1.0.10 \
    && cargo build --release --locked --bin aube

# ========================================
# Stage: noora asset builder
# Builds noora's CSS/JS from source so Atlas can embed the digested output
# in the runtime image. Kept in a separate stage so the Elixir builder
# doesn't need Node/aube in its layer.
# ========================================
FROM node:22-slim@sha256:c3de60bf2f9dd0ac6370e6117950ff62d6e339527e7472301c9c78a017978392 AS noora-assets
COPY infra/certificate-trust/pem-store.sh infra/certificate-trust/policy.json /opt/tuist/certificate-trust/

ENV CI=1
ENV XDG_DATA_HOME="/aube-data"

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && sed -i -e 's|^mozilla/emSign_ECC_Root_CA_-_G3.crt|!&|' -e 's|^mozilla/Comodo_AAA_Services_root.crt|!&|' /etc/ca-certificates.conf \
    && update-ca-certificates && rm -rf /var/lib/apt/lists/*
RUN bash /opt/tuist/certificate-trust/pem-store.sh check /etc/ssl/certs/ca-certificates.crt
ENV NODE_OPTIONS=--use-openssl-ca \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# aube 1.6.2 is the version server/Dockerfile uses to build noora
# assets today. Atlas's inbox worker uses 1.41.0 for its own tests,
# but that newer aube regressed how it invokes esbuild's binary in
# this Docker layer (ELF vs. JS shim mismatch), and pinning to server's
# proven version here keeps this build path stable.
COPY --from=aube-builder /aube/target/release/aube /usr/local/bin/aube

# Install from the manifest alone so the install layer survives source
# changes, then copy only what the build reads: the web component generator
# walks components/ and lib/noora/icons/, and esbuild bundles js/ and css/.
# A rebuilt stage hands the builder new bytes even when the bundles are the
# same, so changes to noora's docs, storybook, or tests must not reach it.
WORKDIR /noora
COPY noora/package.json noora/aube-lock.yaml ./
RUN --mount=type=cache,id=aube,target=/aube-data/aube aube install
COPY noora/scripts scripts
COPY noora/components components
COPY noora/lib/noora/icons lib/noora/icons
COPY noora/js js
COPY noora/css css
RUN aube run build

# ========================================
# Stage: Elixir builder
# ========================================
FROM ${BUILDER_IMAGE} AS builder
COPY infra/certificate-trust/pem-store.sh infra/certificate-trust/policy.json /opt/tuist/certificate-trust/

RUN apt-get update -y && apt-get install -y build-essential git ca-certificates \
    && sed -i -e 's|^mozilla/emSign_ECC_Root_CA_-_G3.crt|!&|' -e 's|^mozilla/Comodo_AAA_Services_root.crt|!&|' /etc/ca-certificates.conf \
    && update-ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*
RUN bash /opt/tuist/certificate-trust/pem-store.sh check /etc/ssl/certs/ca-certificates.crt

ENV HEX_CACERTS_PATH=/etc/ssl/certs/ca-certificates.crt
ENV REBAR_OFFLINE=1
WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV="prod"

# Resolving `{:noora, path: "../noora"}` only needs noora's mix files, so
# its source comes in after the Hex dependencies are fetched and compiled.
# A noora change then recompiles noora alone instead of every dependency.
COPY noora/mix.exs noora/mix.lock /noora/

# install mix dependencies
COPY atlas/mix.exs atlas/mix.lock ./
RUN mix deps.get --only $MIX_ENV

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled. Sources are literal paths: Once can't tell which files
# a COPY with a variable reads, so it keys it on the whole build context,
# and that differs between checkouts.
COPY atlas/config/config.exs atlas/config/prod.exs config/
RUN mix deps.compile

# Noora's modules read README.md and the component contracts at compile
# time. The aube-built priv/static from the noora-assets stage overlays the
# source so Atlas can serve noora's compiled CSS/JS.
COPY noora/README.md /noora/
COPY noora/components /noora/components
COPY noora/lib /noora/lib
COPY --from=noora-assets /noora/priv/static /noora/priv/static
RUN mix deps.compile noora --force

# Copied before the code because they rarely change: every instruction after
# the one an edit invalidates runs again.
COPY atlas/priv priv
COPY atlas/assets assets
COPY atlas/rel rel
COPY atlas/lib lib

# Compile the project (generates colocated hooks needed by esbuild)
RUN mix compile

# compile assets
RUN mix assets.deploy

# Changes to config/runtime.exs don't require recompiling the code
COPY atlas/config/runtime.exs config/

# Version the release independently of the image tag. mix.exs reads it, but
# only the .app file carries it, so it's declared after compilation and only
# the .app file is regenerated. Every release has a new version, and declaring
# it earlier invalidated every layer above.
ARG ATLAS_VERSION=0.1.0
ENV ATLAS_VERSION=${ATLAS_VERSION}
RUN mix compile.app --force && mix release

# ========================================
# Stage: Runner
# ========================================
FROM ${RUNNER_IMAGE}
COPY infra/certificate-trust/pem-store.sh infra/certificate-trust/policy.json /opt/tuist/certificate-trust/

# The release passes its version as APT_CACHE_BUST so a cached layer never
# holds back Debian security patches. CI leaves the default and reuses it.
ARG APT_CACHE_BUST=0
RUN : "APT_CACHE_BUST=${APT_CACHE_BUST}" \
  && apt-get update -y && \
  apt-get install -y libstdc++6 openssl libncurses6 locales ca-certificates poppler-utils pandoc chromium fonts-liberation \
  && sed -i -e 's|^mozilla/emSign_ECC_Root_CA_-_G3.crt|!&|' -e 's|^mozilla/Comodo_AAA_Services_root.crt|!&|' /etc/ca-certificates.conf \
  && update-ca-certificates \
  && apt-get clean && rm -f /var/lib/apt/lists/*_* \
  && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen \
  && mkdir -p /app && chown nobody /app
RUN bash /opt/tuist/certificate-trust/pem-store.sh check /etc/ssl/certs/ca-certificates.crt

# Chromium binary path used by browse_chrome to start headless instances for
# the `browse_url` MCP tool. Set here so the pool boots automatically.
# HOME must be writable for chromium's crashpad child; the `nobody` user
# has no real home directory, so point it at /tmp.
ENV CHROME_PATH=/usr/bin/chromium
ENV HOME=/tmp

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"

# set runner ENV
ENV MIX_ENV="prod"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/prod/rel/atlas ./

USER nobody

# If using an environment that doesn't automatically reap orphaned child
# processes, it is advised to add an init process such as tini via
# temporary `apt-get install tini` in the runner stage, and adding an
# pointpoint. See https://github.com/krallin/tini for details
# ENTRYPOINT ["/tini", "--"]

CMD ["/app/bin/server"]
