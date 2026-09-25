# The image of what runs on a rack's edge node: the rack-edge DaemonSet
# (infra/helm/rack-edge), and the rack boot server in the tuist chart. The tools
# their scripts call, keepalived, and nothing of its own beyond iPXE's Secure
# Boot build.
ARG ALPINE_VERSION=3.22

# iPXE on the firmware's network driver (snponly), which then fetches
# everything else over HTTP, in the iPXE project's Secure Boot build: the
# firmware's PXE loads snponly-shim.efi, a shim signed by Microsoft's UEFI CA,
# and it loads snponly.efi, signed by the iPXE project's CA, which it trusts.
FROM alpine:${ALPINE_VERSION} AS netboot
ARG IPXE_VERSION=2.0.0
ARG IPXE_SHA256=01a526d4cc791fc30362259c609d6c506cc64a7bdff51b9a5eb788354e17eee1
RUN apk add --no-cache curl \
 && curl -fsSL -o /tmp/ipxeboot.tar.gz "https://github.com/ipxe/ipxe/releases/download/v${IPXE_VERSION}/ipxeboot.tar.gz" \
 && echo "${IPXE_SHA256}  /tmp/ipxeboot.tar.gz" | sha256sum -c - \
 && mkdir -p /tmp/ipxe /netboot \
 && tar -xzf /tmp/ipxeboot.tar.gz -C /tmp/ipxe \
 && cp -L /tmp/ipxe/ipxeboot/x86_64-sb/snponly-shim.efi /tmp/ipxe/ipxeboot/x86_64-sb/snponly.efi /netboot/ \
 && test -s /netboot/snponly-shim.efi && test -s /netboot/snponly.efi

FROM alpine:${ALPINE_VERSION}

RUN apk add --no-cache dnsmasq iproute2 nftables keepalived busybox-extras curl libarchive-tools
COPY --from=netboot /netboot/ /usr/share/rack-netboot/
