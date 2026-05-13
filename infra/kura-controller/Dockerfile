FROM golang:1.25-bookworm AS builder
WORKDIR /src
COPY infra/kura-controller/go.mod infra/kura-controller/go.sum* ./
RUN go mod download
COPY infra/kura-controller/ ./
ARG TARGETOS=linux
ARG TARGETARCH=amd64
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -o /out/manager ./cmd/manager

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /out/manager /manager
USER 65532:65532
ENTRYPOINT ["/manager"]
