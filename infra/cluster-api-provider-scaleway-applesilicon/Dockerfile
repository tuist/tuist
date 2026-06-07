# CAPI infrastructure provider for Scaleway Apple Silicon Mac minis.
#
# Owns lifecycle: order/release Mac minis from Scaleway, SSH-bootstrap
# each into a real cluster Node by installing `tart-kubelet`. Three
# darwin/arm64 artifacts ride the linux operator image:
#   - the manager itself (linux/<arch>),
#   - the tart-kubelet binary the operator uploads to each Mac mini at
#     provision and on every drift-detected rolling update,
#   - the upstream `tart.app` tarball pinned via TART_VERSION below
#     (the asset GitHub publishes on each cirruslabs/tart release),
#     which the operator extracts onto the Mac mini at first bootstrap
#     under /usr/local/lib/tart.app.
# One image, one URL pin in the chart, no separate release artifact.

ARG GO_VERSION=1.26
ARG ALPINE_VERSION=3.22

# Tart version pinned for reproducibility. Bump deliberately — Tart 2.x
# minor releases occasionally change VM disk format, and a Mac mini
# already running VMs can't safely have its hypervisor swapped without
# Machine replacement. Update path: bump TART_VERSION here, build a new
# operator image, roll out via Helm. New Mac minis pick up the new
# version on first bootstrap; existing ones keep their installed Tart
# until they're replaced.
ARG TART_VERSION=2.32.1

# Tailscale upstream tag to cross-build from. The tailscale-builder
# stage below clones github.com/tailscale/tailscale at this tag and
# produces darwin/arm64 `tailscale` + `tailscaled` binaries. Pinning
# here makes the tailnet client reproducible across operator
# deploys; bumping is a deliberate Dockerfile change, same
# convention as TART_VERSION. Matches the tailscale-operator
# chart's version pin in infra/helm/tailscale-operator/Chart.yaml so
# the cluster-side operator and the host-side daemons stay in
# lockstep.
ARG TAILSCALE_VERSION=1.96.5

# node_exporter version, pulled as a pre-built darwin/arm64 binary
# from upstream's GitHub release. Prometheus publishes per-OS/arch
# tarballs for every release; we skip the cross-compile dance
# (which needs Apple SDK headers for IOKit/Mach CGo bindings used
# by the diskstats/meminfo/powersupplyclass collectors) and pull
# the upstream-built artifact directly. Same convention as
# TART_VERSION and TAILSCALE_VERSION: deliberate bump via the
# Dockerfile.
ARG NODE_EXPORTER_VERSION=1.8.2

FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine${ALPINE_VERSION} AS manager-builder

# The operator's go.mod has `replace ../macos-host-bootstrap`, so both
# modules land under /src for the build to resolve. We do not COPY
# go.work — workspace mode would expect every module the workspace
# declares (including tart-kubelet) to be present, and only bringing
# two of three into manager-builder would fail.
WORKDIR /src
COPY infra/cluster-api-provider-scaleway-applesilicon/go.mod \
     infra/cluster-api-provider-scaleway-applesilicon/go.sum ./cluster-api-provider-scaleway-applesilicon/
COPY infra/macos-host-bootstrap/go.mod \
     infra/macos-host-bootstrap/go.sum ./macos-host-bootstrap/
WORKDIR /src/cluster-api-provider-scaleway-applesilicon
RUN go mod download

COPY infra/macos-host-bootstrap /src/macos-host-bootstrap
COPY infra/cluster-api-provider-scaleway-applesilicon /src/cluster-api-provider-scaleway-applesilicon

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


FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine${ALPINE_VERSION} AS host-tcp-forwarder-builder

# Tiny multi-connection TCP relay (`infra/host-tcp-forwarder/`). Runs
# on each Mac mini, bridging Tart VM outbound traffic to tailnet-
# exposed cluster Services via the host's tailscale0 interface — the
# VM has no tailnet identity, so without this relay there is no path
# from VM userspace to a tailnet CGNAT address. The bootstrap step
# installs it under launchd, one supervised job per forward.
WORKDIR /src
COPY infra/host-tcp-forwarder/go.mod ./
RUN go mod download
COPY infra/host-tcp-forwarder ./
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    GOOS=darwin GOARCH=arm64 CGO_ENABLED=0 \
    go build -trimpath -ldflags="-s -w" \
    -o /out/host-tcp-forwarder-darwin-arm64 ./cmd/host-tcp-forwarder


FROM --platform=$BUILDPLATFORM alpine:${ALPINE_VERSION} AS tart-fetcher

# Pin Tart at image build time. The asset URL pattern is stable:
# https://github.com/cirruslabs/tart/releases/download/<version>/tart.tar.gz
# The tarball contains `tart.app/` at top level — we ship it as-is and
# the macOS-host-bootstrap step extracts it to /usr/local/lib/tart.app
# on the Mac mini. We don't unpack here because the tarball already
# matches the wire format the bootstrap step pipes into `tar -xzf -`
# over SSH.
ARG TART_VERSION
RUN apk add --no-cache curl
WORKDIR /out
RUN curl -fsSL -o tart.tar.gz \
    "https://github.com/cirruslabs/tart/releases/download/${TART_VERSION}/tart.tar.gz"


FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine${ALPINE_VERSION} AS tailscale-builder

# Tailscale's open-source `tailscaled` variant — what Tailscale's own
# docs designate as the headless-server path on macOS (see
# https://github.com/tailscale/tailscale/wiki/Tailscaled-on-macOS).
# We build the two upstream Go binaries (tailscale, tailscaled) for
# darwin/arm64 from a pinned source tag and ship them as a tarball.
# The bootstrap step extracts to /usr/local/bin and calls
# `tailscaled install-system-daemon`, which writes its own launchd
# plist — the canonical install path for unattended Mac mini servers.
#
# Why not the .pkg installer at pkgs.tailscale.com: that ships the
# GUI Tailscale.app, and its postinstall script runs GUI lifecycle
# work (osascript hooks, etc) that fails on headless hosts when the
# previously-running daemon holds open the binaries being replaced.
# This variant has no GUI app, no postinstall scripts — just the
# daemon, the CLI, and a launchd plist.
#
# CGO_ENABLED=0: tailscaled's darwin backend uses
# golang.org/x/sys/unix for utun device allocation, no Apple SDK
# headers needed.
ARG TAILSCALE_VERSION
RUN apk add --no-cache git
WORKDIR /src
RUN git clone --depth 1 --branch "v${TAILSCALE_VERSION}" \
    https://github.com/tailscale/tailscale .
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    GOOS=darwin GOARCH=arm64 CGO_ENABLED=0 \
    go build -trimpath -ldflags="-s -w" -o /out/tailscale ./cmd/tailscale && \
    GOOS=darwin GOARCH=arm64 CGO_ENABLED=0 \
    go build -trimpath -ldflags="-s -w" -o /out/tailscaled ./cmd/tailscaled
RUN cd /out && tar czf tailscale-darwin-arm64.tar.gz tailscale tailscaled


FROM --platform=$BUILDPLATFORM alpine:${ALPINE_VERSION} AS node-exporter-fetcher

# Upstream's pre-built darwin/arm64 binary. Prometheus publishes
# per-OS/arch tarballs (`node_exporter-<v>.darwin-arm64.tar.gz`)
# for every release — pulls the binary built on their own CI with
# the Apple SDK in scope, so we get the full collector set
# (diskstats, meminfo, powersupplyclass) that a CGO_ENABLED=0
# cross-compile from Linux can't produce.
#
# Tarball layout: `node_exporter-<v>.darwin-arm64/node_exporter`.
# We strip the version-dir on extraction so the binary lands at
# /out/node_exporter-darwin-arm64 regardless of which version is
# pinned.
ARG NODE_EXPORTER_VERSION
RUN apk add --no-cache curl tar
WORKDIR /out
RUN curl -fsSL \
    "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.darwin-arm64.tar.gz" \
    | tar -xz --strip-components=1 "node_exporter-${NODE_EXPORTER_VERSION}.darwin-arm64/node_exporter" \
    && mv node_exporter node_exporter-darwin-arm64


FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=manager-builder /out/manager /usr/local/bin/manager
COPY --from=kubelet-builder /out/tart-kubelet-darwin-arm64 /opt/tart-kubelet/tart-kubelet-darwin-arm64
COPY --from=tart-fetcher /out/tart.tar.gz /opt/tart/tart.tar.gz
COPY --from=tailscale-builder /out/tailscale-darwin-arm64.tar.gz /opt/tailscale/tailscale-darwin-arm64.tar.gz
COPY --from=node-exporter-fetcher /out/node_exporter-darwin-arm64 /opt/node-exporter/node_exporter-darwin-arm64
COPY --from=host-tcp-forwarder-builder /out/host-tcp-forwarder-darwin-arm64 /opt/host-tcp-forwarder/host-tcp-forwarder-darwin-arm64

USER nonroot:nonroot

ENTRYPOINT ["/usr/local/bin/manager"]
