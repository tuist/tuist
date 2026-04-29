# CAPI infrastructure provider for Scaleway Apple Silicon Mac minis.
#
# Owns lifecycle: order/release Mac minis from Scaleway, SSH-bootstrap
# Tart on each. Mac minis are NOT k8s nodes — the Virtual Kubelet
# provider (infra/vk-applesilicon) claims them as Tart slots.

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


FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=manager-builder /out/manager /usr/local/bin/manager

USER nonroot:nonroot

ENTRYPOINT ["/usr/local/bin/manager"]
