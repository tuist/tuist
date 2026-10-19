# Privileged DaemonSet daemon that runs Firecracker microVM sandboxes. See
# AGENTS.md for the architecture and cmd/sandboxd for the entrypoint.
#
# alpine (not distroless): the daemon shells out to `ip` and `iptables` for
# the per-sandbox network namespaces and to `cp --reflink=always` (coreutils)
# as the FICLONE fallback. Root user: it drives the jailer, mknods device
# nodes into chroots and chowns files to per-sandbox uids.
ARG GO_VERSION=1.25
ARG ALPINE_VERSION=3.22
ARG FIRECRACKER_VERSION=v1.16.1
ARG FIRECRACKER_SHA256=382a02a869e4d6d5cb14c40577f9545e8458021ea8b0b2d3fc10ec14d9c242e6

FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine${ALPINE_VERSION} AS builder

WORKDIR /src
COPY infra/sandboxd/go.mod infra/sandboxd/go.sum ./
RUN go mod download

COPY infra/sandboxd ./

ARG TARGETOS
ARG TARGETARCH
ARG VERSION=dev
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    GOOS=${TARGETOS} GOARCH=${TARGETARCH} CGO_ENABLED=0 \
    go build -trimpath -ldflags="-s -w -X main.version=${VERSION}" -o /out/sandboxd ./cmd/sandboxd

# Firecracker release binaries. The tarball unpacks to
# release-<version>-x86_64/{firecracker,jailer,snapshot-editor}-<version>-x86_64.
FROM alpine:${ALPINE_VERSION} AS firecracker
ARG FIRECRACKER_VERSION
ARG FIRECRACKER_SHA256
RUN apk add --no-cache curl \
    && curl -fsSL -o /tmp/firecracker.tgz \
         "https://github.com/firecracker-microvm/firecracker/releases/download/${FIRECRACKER_VERSION}/firecracker-${FIRECRACKER_VERSION}-x86_64.tgz" \
    && echo "${FIRECRACKER_SHA256}  /tmp/firecracker.tgz" | sha256sum -c - \
    && mkdir -p /tmp/fc && tar -xzf /tmp/firecracker.tgz -C /tmp/fc \
    && install -m 0755 "/tmp/fc/release-${FIRECRACKER_VERSION}-x86_64/firecracker-${FIRECRACKER_VERSION}-x86_64" /usr/local/bin/firecracker \
    && install -m 0755 "/tmp/fc/release-${FIRECRACKER_VERSION}-x86_64/jailer-${FIRECRACKER_VERSION}-x86_64" /usr/local/bin/jailer \
    && install -m 0755 "/tmp/fc/release-${FIRECRACKER_VERSION}-x86_64/snapshot-editor-${FIRECRACKER_VERSION}-x86_64" /usr/local/bin/snapshot-editor

FROM alpine:${ALPINE_VERSION}

RUN apk add --no-cache iproute2 iptables e2fsprogs coreutils curl

COPY --from=firecracker /usr/local/bin/firecracker /usr/local/bin/jailer /usr/local/bin/snapshot-editor /usr/local/bin/
COPY --from=builder /out/sandboxd /usr/local/bin/sandboxd

USER 0:0
ENTRYPOINT ["/usr/local/bin/sandboxd"]
