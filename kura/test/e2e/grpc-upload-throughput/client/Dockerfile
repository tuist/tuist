FROM golang:1.25-bookworm AS build
WORKDIR /src
# Build from the committed go.mod + go.sum so dependency versions (and their
# checksums) are pinned and reproducible, rather than re-resolving them from the
# module proxy at build time. Keep them in sync with `go mod tidy` when the
# client's imports change.
COPY go.mod go.sum ./
RUN go mod download
COPY main.go .
RUN CGO_ENABLED=0 go build -mod=readonly -trimpath -o /client .

FROM gcr.io/distroless/static-debian12
COPY --from=build /client /client
ENTRYPOINT ["/client"]
