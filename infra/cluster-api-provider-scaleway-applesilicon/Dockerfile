# CAPI infrastructure provider for Scaleway Apple Silicon Mac minis.
#
# Owns lifecycle: order/release Mac minis from Scaleway, SSH-bootstrap
# each into a real cluster Node by installing `tart-kubelet`. Both the
# operator (linux) and the kubelet (darwin/arm64) are baked into this
# image: the operator reads the kubelet binary off disk and uploads it
# to the Mac mini over SSH at provision + on every drift-detected
# rolling update. One image, one URL pin in the chart, no separate
# release artifact.

ARG GO_VERSION=1.25
ARG ALPINE_VERSION=3.22

FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine${ALPINE_VERSION} AS manager-builder

WORKDIR /src
COPY infra/cluster-api-provider-scaleway-applesilicon/go.mod \
     infra/cluster-api-provider-scaleway-applesilicon/go.sum ./
RUN go mod download

COPY infra/cluster-api-provider-scaleway-applesilicon ./

ARG TARGETOS
ARG TARGETARCH
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    GOOS=${TARGETOS} GOARCH=${TARGETARCH} CGO_ENABLED=0 \
    go build -ldflags="-s -w" -o /out/manager ./cmd/manager


FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine${ALPINE_VERSION} AS kubelet-builder

WORKDIR /src
COPY infra/tart-kubelet/go.mod infra/tart-kubelet/go.sum ./
RUN go mod download

COPY infra/tart-kubelet ./

# Always darwin/arm64 — these binaries run on Mac minis, not on the
# operator host. CGO off keeps the binary statically linked so it has
# no Homebrew dependencies on the target.
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    GOOS=darwin GOARCH=arm64 CGO_ENABLED=0 \
    go build -trimpath -ldflags="-s -w" \
    -o /out/tart-kubelet-darwin-arm64 ./cmd/tart-kubelet


FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=manager-builder /out/manager /usr/local/bin/manager
COPY --from=kubelet-builder /out/tart-kubelet-darwin-arm64 /opt/tart-kubelet/tart-kubelet-darwin-arm64

USER nonroot:nonroot

ENTRYPOINT ["/usr/local/bin/manager"]
