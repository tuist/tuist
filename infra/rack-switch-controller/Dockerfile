ARG GO_VERSION=1.25
ARG ALPINE_VERSION=3.22

FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine${ALPINE_VERSION} AS builder

WORKDIR /src
COPY infra/rack-switch-controller/go.mod infra/rack-switch-controller/go.sum ./
RUN go mod download

COPY infra/rack-switch-controller ./

ARG TARGETOS
ARG TARGETARCH
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    GOOS=${TARGETOS} GOARCH=${TARGETARCH} CGO_ENABLED=0 \
    go build -trimpath -ldflags="-s -w" -o /out/rack-switch-controller ./cmd/manager

FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=builder /out/rack-switch-controller /usr/local/bin/rack-switch-controller

USER nonroot:nonroot

ENTRYPOINT ["/usr/local/bin/rack-switch-controller"]
