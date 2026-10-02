# The image of what runs on a rack's edge node: the rack-edge DaemonSet
# (infra/helm/rack-edge). The tools its scripts call, keepalived, and nothing
# of its own. Of tailscale only the CLI is used, against the node's own
# tailscaled. The rack's boot server runs from the operator's image instead
# (infra/cluster-api-provider-tuist/cmd/rack-boot).
ARG ALPINE_VERSION=3.22

FROM alpine:${ALPINE_VERSION}

RUN apk add --no-cache dnsmasq iproute2 nftables keepalived tailscale
