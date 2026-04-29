# Virtual Kubelet provider for the Scaleway Apple Silicon Mac mini
# fleet. Registers a virtual Node and translates Pods scheduled to it
# into Tart VMs running on Mac minis (driven via SSH).

ARG GO_VERSION=1.25
ARG ALPINE_VERSION=3.22

FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine${ALPINE_VERSION} AS builder

WORKDIR /src
COPY infra/vk-applesilicon/go.mod infra/vk-applesilicon/go.sum ./
RUN go mod download

COPY infra/vk-applesilicon ./

ARG TARGETOS
ARG TARGETARCH
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    GOOS=${TARGETOS} GOARCH=${TARGETARCH} CGO_ENABLED=0 \
    go build -ldflags="-s -w" -o /out/vk-applesilicon ./cmd/vk-applesilicon


FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=builder /out/vk-applesilicon /usr/local/bin/vk-applesilicon

USER nonroot:nonroot

ENTRYPOINT ["/usr/local/bin/vk-applesilicon"]
