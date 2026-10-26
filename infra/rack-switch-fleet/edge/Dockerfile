# The image of what runs on a rack's edge node: the rack-edge DaemonSet
# (infra/helm/rack-edge). The tools its scripts call, keepalived, BIRD for a
# site that announces prefixes of its own, and one program of its own:
# rack-tor-console, which reboots a PicOS ToR that zero-touch provisioning
# missed (tor-console/). Of tailscale only the CLI is used, against the node's
# own tailscaled. The rack's boot server runs from the operator's image instead
# (infra/cluster-api-provider-tuist/cmd/rack-boot).
ARG ALPINE_VERSION=3.22
ARG GO_VERSION=1.26.10

FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine AS tor-console
ARG TARGETOS
ARG TARGETARCH
WORKDIR /src
COPY tor-console/ .
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -ldflags=-s -o /out/rack-tor-console .

FROM alpine:${ALPINE_VERSION}

RUN apk add --no-cache bird2 dnsmasq ethtool iproute2 nftables keepalived tailscale 'ca-certificates>=20261020-r0' \
    && update-ca-certificates
COPY --from=tor-console /out/rack-tor-console /usr/local/bin/rack-tor-console
