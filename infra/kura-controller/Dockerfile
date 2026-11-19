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

FROM gcr.io/distroless/static-debian13:nonroot@sha256:516757106de35205efb70b91ba03f6f1298424a0678c603255cf2852a7000087
COPY --from=builder /out/manager /manager
COPY --from=builder /out/cache-activation /cache-activation
USER 65532:65532
ENTRYPOINT ["/manager"]
