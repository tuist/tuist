FROM golang:1.26.10-alpine3.23 AS build
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY *.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/kube-impersonator .

FROM gcr.io/distroless/static-debian13:nonroot@sha256:8ce6dd87e9823c5b48dcfb2c8604714ccb351ce59607327bcc4957448da279b5
COPY --from=build /out/kube-impersonator /kube-impersonator
USER nonroot:nonroot
EXPOSE 8081
ENTRYPOINT ["/kube-impersonator"]
