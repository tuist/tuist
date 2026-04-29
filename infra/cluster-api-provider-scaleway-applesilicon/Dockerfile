# CAPI infrastructure provider for Scaleway Apple Silicon Mac minis.
#
# The image bundles four things:
#   1. The controller-manager binary (Go) that reconciles
#      ScalewayAppleSiliconMachine CRs against Scaleway's API.
#   2. The tart-cri binary (Go), built for darwin/arm64, which the
#      bootstrap step ships to each provisioned Mac mini.
#   3. The tart-cni binary (Go), same as above.
#   4. The kubelet binary cross-built for darwin/arm64 from upstream
#      Kubernetes source. Kubernetes doesn't publish darwin kubelet
#      builds on dl.k8s.io (Linux-only), so we cross-compile it
#      ourselves and the bootstrap step uploads it like tart-cri.

ARG GO_VERSION=1.25
ARG ALPINE_VERSION=3.22
ARG KUBELET_VERSION=v1.32.1

FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine${ALPINE_VERSION} AS tart-cri-builder

WORKDIR /src
COPY infra/tart-cri/go.mod infra/tart-cri/go.sum ./
RUN go mod download

COPY infra/tart-cri ./
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    GOOS=darwin GOARCH=arm64 CGO_ENABLED=0 \
    go build -ldflags="-s -w" -o /out/tart-cri ./cmd/tart-cri && \
    GOOS=darwin GOARCH=arm64 CGO_ENABLED=0 \
    go build -ldflags="-s -w" -o /out/tart-cni ./cmd/tart-cni


FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine${ALPINE_VERSION} AS kubelet-builder

ARG KUBELET_VERSION
RUN apk add --no-cache git
WORKDIR /src
RUN git clone --depth 1 --branch ${KUBELET_VERSION} https://github.com/kubernetes/kubernetes .
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    GOOS=darwin GOARCH=arm64 CGO_ENABLED=0 \
    go build -ldflags="-s -w" -o /out/kubelet ./cmd/kubelet


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

COPY --from=manager-builder    /out/manager      /usr/local/bin/manager
COPY --from=tart-cri-builder   /out/tart-cri     /usr/local/share/tart-cri/tart-cri
COPY --from=tart-cri-builder   /out/tart-cni     /usr/local/share/tart-cri/tart-cni
COPY --from=kubelet-builder    /out/kubelet      /usr/local/share/tart-cri/kubelet

USER nonroot:nonroot

ENTRYPOINT ["/usr/local/bin/manager"]
