# Tuist runner-cache-proxy: a HOST binary (not an in-cluster service). It
# runs on the runner host (Mac mini / Hetzner node), intercepts guest
# cache traffic via pf/nftables DNAT, and routes the GitHub Actions
# CacheService calls to the local cache-gateway. This image only carries
# the two host binaries so the host-provisioning operator images can ship
# the right one over SSH / cloud-init.

ARG GO_VERSION=1.25
ARG ALPINE_VERSION=3.22

FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine${ALPINE_VERSION} AS builder

WORKDIR /src
COPY infra/runner-cache-proxy/go.mod infra/runner-cache-proxy/go.sum ./
RUN go mod download

COPY infra/runner-cache-proxy ./

RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 \
    go build -trimpath -ldflags="-s -w" -o /out/runner-cache-proxy-darwin-arm64 ./cmd/runner-cache-proxy && \
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags="-s -w" -o /out/runner-cache-proxy-linux-amd64 ./cmd/runner-cache-proxy


FROM scratch

COPY --from=builder /out/ /
