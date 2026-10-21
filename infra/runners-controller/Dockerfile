# Tuist runners-controller: a Go controller-runtime operator that
# reconciles RunnerPool + RunnerAssignment CRDs into Pod + per-Pod
# ServiceAccount pairs on the customer-runners namespace. Runs in
# the chart's release namespace (one Deployment + leader election);
# Pods + SAs it materializes land in tuist-runners.

ARG GO_VERSION=1.26.10
ARG ALPINE_VERSION=3.23

FROM scratch AS certificate-trust
COPY infra/certificate-trust/pem-store.sh infra/certificate-trust/policy.json /

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


# The storage agent needs reflink copies, loop devices and ext4 formatting; keep
# those out of the controller's distroless runtime.
FROM debian:bookworm-slim AS cache-volumes
RUN apt-get update && apt-get install -y --no-install-recommends coreutils util-linux e2fsprogs ca-certificates \
    && sed -i -e 's|^mozilla/emSign_ECC_Root_CA_-_G3.crt|!&|' -e 's|^mozilla/Comodo_AAA_Services_root.crt|!&|' /etc/ca-certificates.conf \
    && update-ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN --mount=type=bind,from=certificate-trust,target=/certificate-trust bash /certificate-trust/pem-store.sh check /etc/ssl/certs/ca-certificates.crt
COPY --from=builder /out/cache-volumes /usr/local/bin/cache-volumes
COPY infra/runners-controller/scripts/provision-cache-filesystem.sh /usr/local/bin/provision-cache-filesystem
ENTRYPOINT ["/usr/local/bin/cache-volumes"]

FROM gcr.io/distroless/static-debian13:nonroot@sha256:516757106de35205efb70b91ba03f6f1298424a0678c603255cf2852a7000087

COPY --from=builder /out/manager /usr/local/bin/manager

USER nonroot:nonroot

ENTRYPOINT ["/usr/local/bin/manager"]
