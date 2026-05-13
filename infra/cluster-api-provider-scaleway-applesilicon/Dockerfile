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

ARG GO_VERSION=1.25
ARG ALPINE_VERSION=3.22

# Tart version pinned for reproducibility. Bump deliberately — Tart 2.x
# minor releases occasionally change VM disk format, and a Mac mini
# already running VMs can't safely have its hypervisor swapped without
# Machine replacement. Update path: bump TART_VERSION here, build a new
# operator image, roll out via Helm. New Mac minis pick up the new
# version on first bootstrap; existing ones keep their installed Tart
# until they're replaced.
ARG TART_VERSION=2.32.1

# Tailscale .pkg pinned at image build time. macOS-only artifact;
# downloaded from pkgs.tailscale.com (Tailscale's own CDN). The
# bootstrap step `scp`s this onto the Mac mini and runs `installer
# -pkg`. Pinning the version here makes the tailnet client
# reproducible across operator deploys — bumping is a deliberate
# Dockerfile change, same convention as TART_VERSION.
#
# Tailscale's CDN only serves the *current* stable .pkg at the
# versioned URL — older versions return 404 once a new stable ships.
# Bumping this ARG is required whenever upstream rolls a new
# release; an out-of-sync value here breaks the build. Matches the
# tailscale-operator chart's version pin in
# infra/helm/tailscale-operator/Chart.yaml.
ARG TAILSCALE_VERSION=1.96.5

# NOTE: node_exporter for darwin/arm64 was previously built here.
# Removed because upstream's 1.8.2 darwin support fails to
# cross-compile with CGO_ENABLED=0 (collector/diskstats_darwin.go +
# meminfo.go + powersupplyclass.go reference symbols that aren't
# defined in CGO-off builds). Host-level metrics are deferred to
# a follow-up PR with a darwin-friendly tool — most likely Grafana
# Alloy in push mode (Alloy ships darwin/arm64 binaries first-
# class and supports hostMetrics out of the box without CGO).
# tart-kubelet's own controller-runtime :8080 endpoint still
# carries the VM-boot histogram, reconcile counts, and error
# rates over the tailnet, so this PR isn't blind on the macOS
# fleet — just without the OS-level CPU/mem/disk series.

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


FROM --platform=$BUILDPLATFORM alpine:${ALPINE_VERSION} AS tailscale-fetcher

# Tailscale's macOS .pkg installer. Drops Tailscale.app under
# /Applications and ships the system-daemon variant — the bootstrap
# runs `Tailscale install-system-daemon` to enable headless operation
# (the default per-user GUI agent doesn't survive the auto-login
# session reshuffling Virtualization.framework demands).
ARG TAILSCALE_VERSION
RUN apk add --no-cache curl
WORKDIR /out
RUN curl -fsSL -o tailscale.pkg \
    "https://pkgs.tailscale.com/stable/Tailscale-${TAILSCALE_VERSION}-macos.pkg"


FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=manager-builder /out/manager /usr/local/bin/manager
COPY --from=kubelet-builder /out/tart-kubelet-darwin-arm64 /opt/tart-kubelet/tart-kubelet-darwin-arm64
COPY --from=tart-fetcher /out/tart.tar.gz /opt/tart/tart.tar.gz
COPY --from=tailscale-fetcher /out/tailscale.pkg /opt/tailscale/tailscale.pkg

USER nonroot:nonroot

ENTRYPOINT ["/usr/local/bin/manager"]
