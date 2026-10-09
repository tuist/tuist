# WireGuard gateway that relays Mac runner host traffic to the internet. See
# AGENTS.md. alpine (not distroless) because the agent applies its ruleset with
# `nft -f -`. Runs as root: it creates wg0, writes the ip_forward sysctl and
# loads nftables in the pod network namespace.
ARG GO_VERSION=1.25
ARG ALPINE_VERSION=3.22

FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine${ALPINE_VERSION} AS builder

WORKDIR /src
COPY infra/runner-egress-gateway/go.mod infra/runner-egress-gateway/go.sum ./
RUN go mod download

COPY infra/runner-egress-gateway ./

ARG TARGETOS
ARG TARGETARCH
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    GOOS=${TARGETOS} GOARCH=${TARGETARCH} CGO_ENABLED=0 \
    go build -trimpath -ldflags="-s -w" -o /out/gateway ./cmd/gateway

FROM alpine:${ALPINE_VERSION}

RUN apk add --no-cache nftables

COPY --from=builder /out/gateway /usr/local/bin/gateway

USER 0:0
ENTRYPOINT ["/usr/local/bin/gateway"]
