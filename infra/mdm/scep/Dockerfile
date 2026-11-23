# micromdm/scep publishes no container image; build scepserver from the
# pinned upstream tag. Bump SCEP_VERSION deliberately.
FROM golang:1.26.10 AS build
ARG SCEP_VERSION=v2.3.0
RUN CGO_ENABLED=0 go install github.com/micromdm/scep/v2/cmd/scepserver@${SCEP_VERSION} \
    && mv /go/bin/scepserver /out-scepserver

FROM gcr.io/distroless/static-debian13:latest@sha256:4c2cd1dee442c9a99924a378c7c126fac8fef14771579ef567c3f2bdd7a5122a
COPY --from=build /out-scepserver /app/scepserver
EXPOSE 8080
ENTRYPOINT ["/app/scepserver"]
