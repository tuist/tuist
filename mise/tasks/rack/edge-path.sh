#!/usr/bin/env bash
#MISE description="Route the rack switches' management addresses into the tailnet through the edge node"
#
# The switches behind the rack's edge node reach the Omada controller, which
# lives on the tailnet, through that node. This installs the edge node's half:
# an address on the switches' port, a host route to each, forwarding, and
# translation into tailscale0. It never advertises a route.
#
#   mise run rack:edge-path --interface enp89s0 --dry-run
#   mise run rack:edge-path --interface enp89s0
#
# See infra/rack-switch-fleet/AGENTS.md.

set -euo pipefail

root="$(git rev-parse --show-toplevel)"
exec "$root/infra/rack-switch-fleet/edge-path.sh" "$@"
