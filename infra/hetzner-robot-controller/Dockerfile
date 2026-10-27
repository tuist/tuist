# Tuist hetzner-robot-controller: a Go controller-runtime
# operator that reflects Hetzner Robot's server inventory into
# `HetznerBareMetalHost` CRs (so caph has something to claim) and
# auto-fills disk WWNs from caph's hardwareDetails (so the install
# flow doesn't stall on empty rootDeviceHints). Runs on the mgmt
# cluster as a small Deployment with leader election.

ARG GO_VERSION=1.25
ARG ALPINE_VERSION=3.22

FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine${ALPINE_VERSION} AS builder

WORKDIR /src
COPY infra/hetzner-robot-controller/go.mod infra/hetzner-robot-controller/go.sum ./
RUN go mod download

COPY infra/hetzner-robot-controller ./

ARG TARGETOS
ARG TARGETARCH
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    GOOS=${TARGETOS} GOARCH=${TARGETARCH} CGO_ENABLED=0 \
    go build -trimpath -ldflags="-s -w" -o /out/manager ./cmd/manager


FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=builder /out/manager /usr/local/bin/manager

USER nonroot:nonroot

ENTRYPOINT ["/usr/local/bin/manager"]
