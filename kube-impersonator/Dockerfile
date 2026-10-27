FROM golang:1.23-alpine AS build
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY *.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/kube-impersonator .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/kube-impersonator /kube-impersonator
USER nonroot:nonroot
EXPOSE 8081
ENTRYPOINT ["/kube-impersonator"]
