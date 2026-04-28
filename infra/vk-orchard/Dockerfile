# Build the Virtual Kubelet provider for the Tuist Orchard fleet.
#
# Two stages: a Go builder (multi-arch — image runs on Linux nodes
# inside the cluster, not on macOS) and a distroless runtime so the
# resulting image stays small and has no shell surface.

ARG GO_VERSION=1.25
ARG ALPINE_VERSION=3.20

FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine${ALPINE_VERSION} AS builder

WORKDIR /src

ARG TARGETOS
ARG TARGETARCH

# Cache module downloads in a separate layer.
COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -ldflags="-s -w" -o /out/vk-orchard ./cmd/vk-orchard

# distroless/static is the smallest base that still has /etc/passwd, CA
# certs, and timezone data — everything a Go binary that talks HTTPS to
# k8s + Orchard needs.
FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=builder /out/vk-orchard /usr/local/bin/vk-orchard

# kubelet API port. The HTTP server in main.go binds here for kubectl
# logs / exec / port-forward routing through the runtime.
EXPOSE 10250

USER nonroot:nonroot

ENTRYPOINT ["/usr/local/bin/vk-orchard"]
