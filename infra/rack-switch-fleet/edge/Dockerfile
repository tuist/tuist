# The rack-edge DaemonSet's image (infra/helm/rack-edge): the tools the edge
# node's rendered files call, and nothing of its own.
ARG ALPINE_VERSION=3.22

FROM alpine:${ALPINE_VERSION}

RUN apk add --no-cache dnsmasq iproute2 nftables
