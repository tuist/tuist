# The image of what runs on a rack's edge node: the rack-edge DaemonSet
# (infra/helm/rack-edge), and the rack boot server in the tuist chart. The tools
# their scripts call, keepalived, and nothing of its own beyond Ubuntu's build
# of iPXE.
ARG ALPINE_VERSION=3.22
ARG UBUNTU_VERSION=24.04

# iPXE on the firmware's network driver (snponly), which the firmware's PXE
# loads and which then fetches everything else over HTTP. An EFI binary for
# amd64 whatever the image's own architecture.
FROM --platform=linux/amd64 ubuntu:${UBUNTU_VERSION} AS netboot
RUN apt-get update \
 && cd /tmp \
 && apt-get download ipxe \
 && mkdir -p /netboot \
 && dpkg-deb --fsys-tarfile ipxe_*.deb | tar -xO ./usr/lib/ipxe/snponly.efi > /netboot/snponly.efi \
 && test -s /netboot/snponly.efi

FROM alpine:${ALPINE_VERSION}

RUN apk add --no-cache dnsmasq iproute2 nftables keepalived busybox-extras curl libarchive-tools
COPY --from=netboot /netboot/ /usr/share/rack-netboot/
