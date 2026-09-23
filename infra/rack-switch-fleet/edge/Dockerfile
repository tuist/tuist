# The image of what runs on a rack's edge node: the rack-edge DaemonSet
# (infra/helm/rack-edge), and the rack boot server in the tuist chart. The tools
# their scripts call, and nothing of its own beyond Ubuntu's signed network
# GRUB.
ARG ALPINE_VERSION=3.22
ARG UBUNTU_VERSION=24.04

# Ubuntu's network GRUB, signed by Canonical, which the installer ISO's shim
# loads, so a netbooting host boots with Secure Boot on. An EFI binary for
# amd64 whatever the image's own architecture.
FROM --platform=linux/amd64 ubuntu:${UBUNTU_VERSION} AS netboot
RUN apt-get update \
 && cd /tmp \
 && apt-get download grub-efi-amd64-signed \
 && mkdir -p /netboot \
 && dpkg-deb --fsys-tarfile grub-efi-amd64-signed_*.deb | tar -xO ./usr/lib/grub/x86_64-efi-signed/grubnetx64.efi.signed > /netboot/grubx64.efi \
 && test -s /netboot/grubx64.efi

FROM alpine:${ALPINE_VERSION}

RUN apk add --no-cache dnsmasq iproute2 nftables busybox-extras curl libarchive-tools
COPY --from=netboot /netboot/ /usr/share/rack-netboot/
