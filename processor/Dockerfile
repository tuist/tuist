ARG ELIXIR_VERSION=1.19.1
ARG OTP_VERSION=27.3.4
ARG DEBIAN_VERSION=bookworm-20260406-slim
ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

# ========================================
# Stage 1: Build Swift NIF library
# ========================================
FROM swift:6.2-bookworm AS swift-builder

RUN apt-get update -qq && apt-get install -y -qq unzip > /dev/null 2>&1 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /nif

COPY processor/native/xcactivitylog_nif/Package.swift .
COPY processor/native/xcactivitylog_nif/Package.resolved .
COPY processor/native/xcactivitylog_nif/Sources/ Sources/
COPY processor/native/xcactivitylog_nif/Tests/ Tests/
COPY processor/native/xcactivitylog_nif/.swiftpm/ .swiftpm/

RUN swift build -c release --replace-scm-with-registry && \
    cp .build/release/libXCActivityLogNIF.so /nif/libXCActivityLogNIF.so && \
    mkdir -p /nif/swift-libs && \
    cp -a /usr/lib/swift/linux/lib*.so* /nif/swift-libs/

# ========================================
# Stage 2: Build Elixir release + NIF bridge
# ========================================
FROM ${BUILDER_IMAGE} AS elixir-builder

RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV=prod

COPY tuist_common /tuist_common
COPY processor/mix.exs processor/mix.lock ./
RUN mix deps.get --only prod

COPY processor/config/config.exs processor/config/prod.exs config/
RUN mix deps.compile

COPY processor/lib lib
RUN mix compile

COPY processor/config/runtime.exs config/

# Copy Swift .so from stage 1 and compile C NIF bridge
COPY processor/native/xcactivitylog_nif/nif_bridge.c /tmp/nif/nif_bridge.c
COPY --from=swift-builder /nif/libXCActivityLogNIF.so /tmp/nif/libXCActivityLogNIF.so

RUN mkdir -p priv/native && \
    ERL_INCLUDE=$(erl -eval 'io:format("~s/erts-~s/include", [code:root_dir(), erlang:system_info(version)])' -s init stop -noshell) && \
    cc -shared -fPIC \
      -o priv/native/xcactivitylog_nif.so \
      /tmp/nif/nif_bridge.c \
      -I"$ERL_INCLUDE" \
      -L/tmp/nif \
      -lXCActivityLogNIF \
      -Wl,-rpath,'$ORIGIN' && \
    cp /tmp/nif/libXCActivityLogNIF.so priv/native/

RUN mix release

# ========================================
# Stage 3: Runtime
# ========================================
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates curl \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Swift runtime libraries needed by the NIF
COPY --from=swift-builder /nif/swift-libs/ /usr/local/lib/
RUN ldconfig

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app

COPY --from=elixir-builder /app/_build/prod/rel/processor ./

ENV PHX_SERVER=true

CMD ["/app/bin/processor", "start"]
