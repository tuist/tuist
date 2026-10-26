FROM golang:1.26.10-alpine AS build
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY *.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/kube-impersonator .

FROM gcr.io/distroless/static-debian13:nonroot@sha256:516757106de35205efb70b91ba03f6f1298424a0678c603255cf2852a7000087
COPY --from=build /out/kube-impersonator /kube-impersonator
USER nonroot:nonroot
EXPOSE 8081
ENTRYPOINT ["/kube-impersonator"]
