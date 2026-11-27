FROM --platform=$BUILDPLATFORM golang:1.26.10-alpine3.23 AS builder

WORKDIR /src
COPY infra/cloudflare-operator/go.mod infra/cloudflare-operator/go.sum ./
RUN go mod download

COPY infra/cloudflare-operator ./

ARG TARGETOS
ARG TARGETARCH
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    GOOS=${TARGETOS} GOARCH=${TARGETARCH} CGO_ENABLED=0 \
    go build -trimpath -ldflags="-s -w" -o /out/manager ./cmd/manager

FROM gcr.io/distroless/static-debian13:nonroot@sha256:8ce6dd87e9823c5b48dcfb2c8604714ccb351ce59607327bcc4957448da279b5

COPY --from=builder /out/manager /usr/local/bin/manager

USER nonroot:nonroot

ENTRYPOINT ["/usr/local/bin/manager"]
