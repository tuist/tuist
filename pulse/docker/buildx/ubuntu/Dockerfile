# Modified by Tuist; see pulse/FORK.md.
FROM ubuntu:22.04 AS builder

ARG CARGO_PROFILE
ARG FEATURES
ARG OUTPUT_DIR

ENV LANG=en_US.utf8
WORKDIR /greptimedb

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y software-properties-common

# Install dependencies.
RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && apt-get install -y \
    libssl-dev \
    curl \
    git \
    build-essential \
    pkg-config \
    unzip

# Tuist: apt's protoc (3.12) cannot compile substrait's proto3 optional
# fields; install the release upstream's dev-builder uses (amd64 only).
ARG PROTOBUF_VERSION=29.3
ARG PROTOBUF_SHA256=3e866620c5be27664f3d2fa2d656b5f3e09b5152b42f1bedbf427b333e90021a
RUN curl -fsSLo /tmp/protoc.zip https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOBUF_VERSION}/protoc-${PROTOBUF_VERSION}-linux-x86_64.zip && \
    echo "${PROTOBUF_SHA256}  /tmp/protoc.zip" | sha256sum -c - && \
    unzip -q /tmp/protoc.zip -d /usr/local bin/protoc 'include/*' && \
    rm /tmp/protoc.zip && \
    protoc --version

# Install Rust.
SHELL ["/bin/bash", "-c"]
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --no-modify-path --default-toolchain none -y
ENV PATH=/root/.cargo/bin/:$PATH

# Build the project in release mode.
RUN --mount=target=. \
    --mount=type=cache,target=/root/.cargo/registry \
    make build \
    CARGO_PROFILE=${CARGO_PROFILE} \
    FEATURES=${FEATURES} \
    TARGET_DIR=/out/target

# Export the binary to the clean image.
# TODO(zyy17): Maybe should use the more secure container image.
FROM ubuntu:22.04 AS base

ARG OUTPUT_DIR

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get \
    -y install ca-certificates \
    curl

WORKDIR /greptime
COPY --from=builder /out/target/${OUTPUT_DIR}/greptime /greptime/bin/
ENV PATH=/greptime/bin/:$PATH

ENV MALLOC_CONF="prof:true,prof_active:false"

ENTRYPOINT ["greptime"]
