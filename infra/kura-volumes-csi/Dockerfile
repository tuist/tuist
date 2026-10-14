# Node plugin for the kura-volumes.tuist.dev CSI driver. See AGENTS.md.
#
# Ubuntu (not alpine/distroless): the driver shells out to cryptsetup,
# losetup, mount and mkfs.xfs, and noble ships the same cryptsetup and
# xfsprogs generation as the hosts, so LUKS2 headers and XFS feature flags
# written from the container match what the host tooling expects.
ARG GO_VERSION=1.25
ARG ALPINE_VERSION=3.22
ARG UBUNTU_VERSION=24.04

FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine${ALPINE_VERSION} AS builder

WORKDIR /src
COPY infra/kura-volumes-csi/go.mod infra/kura-volumes-csi/go.sum ./
RUN go mod download

COPY infra/kura-volumes-csi ./

ARG TARGETOS
ARG TARGETARCH
ARG VERSION=dev
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    GOOS=${TARGETOS} GOARCH=${TARGETARCH} CGO_ENABLED=0 \
    go build -trimpath -ldflags="-s -w -X main.version=${VERSION}" -o /out/kura-volumes-csi ./cmd/kura-volumes-csi

FROM ubuntu:${UBUNTU_VERSION}

# ca-certificates: the key fetch verifies the server's public TLS certificate.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates cryptsetup-bin xfsprogs util-linux mount \
    && rm -rf /var/lib/apt/lists/* \
    && test -s /etc/ssl/certs/ca-certificates.crt

COPY --from=builder /out/kura-volumes-csi /usr/local/bin/kura-volumes-csi

USER 0:0
ENTRYPOINT ["/usr/local/bin/kura-volumes-csi"]
