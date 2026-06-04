# Tuist cache-gateway: terminates the GitHub Actions cache v2 protocol
# (Twirp coordination + Azure Block Blob transfer) inside a runner fleet
# and translates it to S3 against a co-located SeaweedFS cluster. One
# instance per fleet, fronted by the host-side runner-cache-proxy.

ARG GO_VERSION=1.25
ARG ALPINE_VERSION=3.22

FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine${ALPINE_VERSION} AS builder

WORKDIR /src
COPY infra/cache-gateway/go.mod infra/cache-gateway/go.sum ./
RUN go mod download

COPY infra/cache-gateway ./

ARG TARGETOS
ARG TARGETARCH
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    GOOS=${TARGETOS} GOARCH=${TARGETARCH} CGO_ENABLED=0 \
    go build -trimpath -ldflags="-s -w" -o /out/cache-gateway ./cmd/cache-gateway


FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=builder /out/cache-gateway /usr/local/bin/cache-gateway

USER nonroot:nonroot

ENTRYPOINT ["/usr/local/bin/cache-gateway"]
