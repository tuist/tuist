FROM golang:1.25-bookworm AS builder
WORKDIR /src
COPY infra/kura-controller/go.mod infra/kura-controller/go.sum* ./
RUN go mod download
COPY infra/kura-controller/ ./
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/manager ./cmd/manager

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /out/manager /manager
USER 65532:65532
ENTRYPOINT ["/manager"]

