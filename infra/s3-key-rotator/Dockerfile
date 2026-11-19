FROM --platform=$BUILDPLATFORM golang:1.26.10-alpine3.23 AS builder

WORKDIR /src
COPY infra/s3-key-rotator/go.mod infra/s3-key-rotator/go.sum ./
RUN go mod download

COPY infra/s3-key-rotator ./

ARG TARGETOS
ARG TARGETARCH
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    GOOS=${TARGETOS} GOARCH=${TARGETARCH} CGO_ENABLED=0 \
    go build -trimpath -ldflags="-s -w" -o /out/rotator ./cmd/rotator

FROM gcr.io/distroless/static-debian13:nonroot@sha256:516757106de35205efb70b91ba03f6f1298424a0678c603255cf2852a7000087

COPY --from=builder /out/rotator /usr/local/bin/rotator

USER nonroot:nonroot

ENTRYPOINT ["/usr/local/bin/rotator"]
