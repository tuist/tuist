#!/usr/bin/env bash
#MISE description="Prepare a BER1 rack switch over its USB-C console (hostname, management IP, SSH)"
#
# A factory switch ships on 192.168.0.1 with SSH disabled, which collides with
# the gateway of most networks it is unboxed on. The console port does not care
# about addressing, so first-touch provisioning happens there: this names the
# switch, gives it the fixed management address from
# infra/rack-switch-prep/switches.json, enables SSH and saves the config.
#
# Connect a USB-C cable from this machine to the switch's console port first.
#
# Usage:
#   mise run rack:prep-switch <switch> [--verbose] [--dry-run] [--create-credentials]
#   e.g. mise run rack:prep-switch ber1-tor-a
#
# The admin login comes from the 1Password item named in switches.json (account
# override: OP_ACCOUNT). Pass --create-credentials on a switch's first run to
# generate it. See infra/rack-switch-prep/AGENTS.md for what the script does not
# do, and for the console baud rate and firmware-line traps.

set -euo pipefail

switch="${1:-}"

if [ -z "$switch" ]; then
  echo "usage: mise run rack:prep-switch <switch> [flags]" >&2
  echo "  e.g. mise run rack:prep-switch ber1-tor-a" >&2
  exit 2
fi

root="$(git rev-parse --show-toplevel)"

exec python3 "$root/infra/rack-switch-prep/prep_switch.py" "$@"
