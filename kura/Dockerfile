FROM rust:1.94.1-bookworm AS build

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      build-essential \
      clang \
      cmake \
      pkg-config && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Cargo.toml Cargo.lock ./
COPY src src

RUN cargo build --release --locked

FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      tini \
      libstdc++6 && \
    rm -rf /var/lib/apt/lists/*

ENV RUST_LOG=info

WORKDIR /app

COPY --from=build /app/target/release/kura /usr/local/bin/kura

EXPOSE 4000

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/kura"]
