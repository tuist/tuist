#!/usr/bin/env bash
#MISE description="Serve DHCP and TFTP on an isolated segment so a switch provisions itself"
#
# Zero touch, the half this hardware already has. A factory switch with Auto
# Install armed boots, asks for an address and a boot file, fetches it and
# applies it, and the USB-C cable stops being part of racking a switch.
#
#   mise run rack:ztp ber1-mgmt --interface en7 --dry-run
#   mise run rack:ztp ber1-mgmt --interface en7
#   mise run rack:ztp ber1-mgmt --via tuist@<ber1-edge-a> --interface enp89s0 [--create-credentials]
#
# --interface is required and must be an isolated segment: a USB Ethernet
# adapter with only the switch on the other end. This serves DHCP, and a second
# DHCP server on a network with people on it hands addresses to their laptops.
# It refuses to run on the interface carrying the default route.

set -euo pipefail

root="$(git rev-parse --show-toplevel)"
exec "$root/infra/rack-switch-fleet/ztp.sh" "$@"
