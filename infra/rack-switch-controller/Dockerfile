FROM --platform=$BUILDPLATFORM golang:1.26.10-alpine3.23 AS builder

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

FROM gcr.io/distroless/static-debian13:nonroot@sha256:8ce6dd87e9823c5b48dcfb2c8604714ccb351ce59607327bcc4957448da279b5

COPY --from=builder /out/rack-switch-controller /usr/local/bin/rack-switch-controller

USER nonroot:nonroot

ENTRYPOINT ["/usr/local/bin/rack-switch-controller"]
