# micromdm/scep publishes no container image; build scepserver from the
# pinned upstream tag. Bump SCEP_VERSION deliberately.
FROM golang:1.25 AS build
ARG SCEP_VERSION=v2.3.0
RUN CGO_ENABLED=0 go install github.com/micromdm/scep/v2/cmd/scepserver@${SCEP_VERSION} \
    && mv /go/bin/scepserver /out-scepserver

FROM gcr.io/distroless/static
COPY --from=build /out-scepserver /app/scepserver
EXPOSE 8080
ENTRYPOINT ["/app/scepserver"]
