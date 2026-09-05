FROM golang:1.25 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -o /out/mdm-enroller .

FROM gcr.io/distroless/static:nonroot
COPY --from=build /out/mdm-enroller /app/mdm-enroller
EXPOSE 9004
ENTRYPOINT ["/app/mdm-enroller"]
