# Tuist runners-controller: a Go controller-runtime operator that
# reconciles RunnerPool + RunnerAssignment CRDs into Pod + per-Pod
# ServiceAccount pairs on the customer-runners namespace. Runs in
# the chart's release namespace (one Deployment + leader election);
# Pods + SAs it materializes land in tuist-runners.

ARG GO_VERSION=1.25
ARG ALPINE_VERSION=3.22

FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine${ALPINE_VERSION} AS builder

WORKDIR /src/runners-controller
COPY infra/runner-cache /src/runner-cache
COPY infra/runners-controller/go.mod infra/runners-controller/go.sum ./
RUN go mod download

COPY infra/runners-controller ./

ARG TARGETOS
ARG TARGETARCH
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    GOOS=${TARGETOS} GOARCH=${TARGETARCH} CGO_ENABLED=0 \
    go build -trimpath -ldflags="-s -w" -o /out/manager ./cmd/manager && \
    GOOS=${TARGETOS} GOARCH=${TARGETARCH} CGO_ENABLED=0 \
    go build -trimpath -ldflags="-s -w" -o /out/cache-volumes ./cmd/cache-volumes


# The git-lfs the checkout populator runs, pinned and verified before it is
# installed: it runs as root on trees from customer repositories.
FROM --platform=$BUILDPLATFORM alpine:${ALPINE_VERSION} AS git-lfs
ARG TARGETARCH
ARG GIT_LFS_VERSION=3.8.0
RUN set -eu; \
    case "$TARGETARCH" in \
      amd64) sum=e455e00f15d9b95661b8d53498ffb0c3367962cf1ec73c31ab7369516cd6ab8d ;; \
      arm64) sum=ac9c8efac980bb0505ead384d087e2acb6486fd8498691a2165fa174ec6118c2 ;; \
      *) echo "no pinned git-lfs for $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    wget -q -O /tmp/git-lfs.tar.gz "https://github.com/git-lfs/git-lfs/releases/download/v${GIT_LFS_VERSION}/git-lfs-linux-${TARGETARCH}-v${GIT_LFS_VERSION}.tar.gz"; \
    echo "$sum  /tmp/git-lfs.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/git-lfs.tar.gz -C /tmp; \
    install -D -m 0755 "/tmp/git-lfs-${GIT_LFS_VERSION}/git-lfs" /out/git-lfs

# The storage agent needs reflink copies, loop devices and ext4 formatting, and
# git with the pinned git-lfs to build cached checkouts; keep those out of the
# controller's distroless runtime.
FROM debian:bookworm-slim AS cache-volumes
RUN apt-get update && apt-get install -y --no-install-recommends coreutils util-linux mount e2fsprogs ca-certificates git \
    && rm -rf /var/lib/apt/lists/*
COPY --from=git-lfs /out/git-lfs /usr/local/bin/git-lfs
COPY --from=builder /out/cache-volumes /usr/local/bin/cache-volumes
COPY infra/runners-controller/scripts/provision-cache-filesystem.sh /usr/local/bin/provision-cache-filesystem
ENTRYPOINT ["/usr/local/bin/cache-volumes"]

FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=builder /out/manager /usr/local/bin/manager

USER nonroot:nonroot

ENTRYPOINT ["/usr/local/bin/manager"]
