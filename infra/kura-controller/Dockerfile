FROM --platform=$BUILDPLATFORM golang:1.26.10-bookworm AS builder
WORKDIR /src
COPY infra/kura-controller/go.mod infra/kura-controller/go.sum* ./
RUN go mod download
COPY infra/kura-controller/ ./
ARG TARGETOS
ARG TARGETARCH
RUN test -n "${TARGETOS}" && \
    test -n "${TARGETARCH}" && \
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -o /out/manager ./cmd/manager && \
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -o /out/cache-activation ./cmd/cache-activation

FROM gcr.io/distroless/static-debian13:nonroot@sha256:8ce6dd87e9823c5b48dcfb2c8604714ccb351ce59607327bcc4957448da279b5
COPY --from=builder /out/manager /manager
COPY --from=builder /out/cache-activation /cache-activation
USER 65532:65532
ENTRYPOINT ["/manager"]
