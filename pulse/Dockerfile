# Pulse release image. Adapted from `mix phx.gen.release --docker`:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags for the builder image
#   - https://hub.docker.com/_/debian/tags?name=trixie for the runner image
#   - https://bob.hex.pm/docker?repo=hexpm/elixir&os=debian&sort=elixir_version,erlang_version,os_version
#
# Versions here mirror mise.toml (elixir 1.20.4, OTP 29.1) and the Debian
# base is trixie for both stages, per Phoenix's own recommendation.
#
# Pulse's Rust NIFs (native/pulse_codec, native/pulse_object_store,
# native/pulse_grpc) ship
# via rustler_precompiled. In this image we compile them from source
# (PULSE_NIF_FORCE_BUILD=1) rather than fetching the precompiled tarball
# from GitHub Releases, so the image can build cleanly for a fresh
# version tag *before* the tag-triggered NIF release workflow has
# published its artifacts.

ARG ELIXIR_VERSION=1.20.4
ARG OTP_VERSION=29.1
ARG DEBIAN_VERSION=trixie-20260918-slim
# Tracks the crate floor in the Cargo.lock files under native/.
# rustler 0.38 and its transitive deps have been pushing the required
# rustc up regularly (1.88 for icu_collections, 1.91 for rustler
# itself), and pinning to a specific minor keeps breaking. ci.yml uses
# `dtolnay/rust-toolchain@stable`, so `stable` here builds against the
# same rustc PRs are already exercising.
ARG RUST_VERSION=stable

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

# Build deps, plus the Rust toolchain for the NIFs. clang is pulled in
# because ring (a transitive Rust dep of the S3 client stack) links
# against it.
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
       build-essential \
       ca-certificates \
       clang \
       curl \
       git \
       pkg-config \
  && rm -rf /var/lib/apt/lists/*

ARG RUST_VERSION
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
  | sh -s -- -y --default-toolchain "${RUST_VERSION}" --profile minimal --no-modify-path

WORKDIR /app

RUN mix local.hex --force \
  && mix local.rebar --force

# Compile NIFs from source; skip the rustler_precompiled fetch.
ENV MIX_ENV="prod" \
    PULSE_NIF_FORCE_BUILD="1"

# Cache mix deps ahead of the source copy.
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Compile-time config first so any change re-triggers dep compilation.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# native/ has to be in place before `mix compile` runs, since
# `use RustlerPrecompiled` compiles the crate as a compile-time side
# effect of the module compile.
COPY native native
COPY priv priv
COPY lib lib

RUN mix compile

# runtime.exs is loaded on boot, not at compile time.
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

FROM ${RUNNER_IMAGE} AS final

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
       ca-certificates \
       libncurses6 \
       libstdc++6 \
       locales \
       openssl \
  && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

ENV MIX_ENV="prod"

COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/pulse ./

USER nobody

CMD ["/app/bin/server"]
