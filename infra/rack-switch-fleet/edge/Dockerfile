# The image of what runs on a rack's edge node: the rack-edge DaemonSet
# (infra/helm/rack-edge). The tools its scripts call, keepalived, BIRD for a
# site that announces prefixes of its own, and nothing of its own. Of tailscale only the CLI is used, against the node's own
# tailscaled. The rack's boot server runs from the operator's image instead
# (infra/cluster-api-provider-tuist/cmd/rack-boot).
ARG ALPINE_VERSION=3.22

FROM alpine:${ALPINE_VERSION}

RUN apk add --no-cache bird2 dnsmasq ethtool iproute2 nftables keepalived tailscale 'ca-certificates>=20261020-r0' \
    && update-ca-certificates
