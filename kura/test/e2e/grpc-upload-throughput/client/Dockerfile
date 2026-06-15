FROM golang:1.25-bookworm AS build
WORKDIR /src
COPY go.mod .
COPY main.go .
# go.sum is generated here so the harness has no committed lockfile to drift;
# tidy resolves the bytestream submodule and transitive deps.
RUN go mod tidy
RUN CGO_ENABLED=0 go build -trimpath -o /client .

FROM gcr.io/distroless/static-debian12
COPY --from=build /client /client
ENTRYPOINT ["/client"]
