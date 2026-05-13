# Tuist runners-controller: a Go controller-runtime operator that
# reconciles RunnerPool + RunnerAssignment CRDs into Pod + per-Pod
# ServiceAccount pairs on the customer-runners namespace. Runs in
# the chart's release namespace (one Deployment + leader election);
# Pods + SAs it materializes land in tuist-runners.

ARG GO_VERSION=1.25
ARG ALPINE_VERSION=3.22

FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine${ALPINE_VERSION} AS builder

WORKDIR /src
COPY infra/runners-controller/go.mod infra/runners-controller/go.sum ./
RUN go mod download

COPY infra/runners-controller ./

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
