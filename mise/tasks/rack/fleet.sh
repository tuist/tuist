#!/usr/bin/env bash
#MISE description="Render, diff, apply, back up and drift-check a rack's switch fleet configuration"
#
# rack:prep-switch gives one switch an identity over its console. This owns
# everything after that: the configuration that applies to a rack's switches as
# a set, rendered from infra/rack-switch-fleet/sites/<site>.json so a switch in
# a future rack differs from ber1's only in site variables.
#
# The configuration in git is the desired state; the switch is compared against
# it rather than trusted. Changing a switch in the web UI during an incident is
# legitimate and will happen, which is what `drift` is for: it finds the change
# so it can be landed in git the same day.
#
# Usage:
#   mise run rack:fleet render                  # write the desired configs
#   mise run rack:fleet render --check          # fail if they are out of date
#   mise run rack:fleet diff [device]           # live switch vs the render
#   mise run rack:fleet apply <device> --dry-run
#   mise run rack:fleet apply <device>
#   mise run rack:fleet backup [device]         # startup config into the repo
#   mise run rack:fleet drift                   # every switch; non-zero on drift
#   mise run rack:fleet probe-tftp <device>     # is the TFTP export text?
#
# --site selects the rack (default ber1). Switches are reached by the SSH key
# named in the site definition; the admin password stays in 1Password and is
# only used by rack:prep-switch over the console.
#
# Switches are applied one at a time in the order the site definition gives, and
# `apply` refuses a switch whose predecessors have not been brought up to the
# render yet. See infra/rack-switch-fleet/AGENTS.md for why that order is what
# it is.

set -euo pipefail

if (( BASH_VERSINFO[0] < 4 )); then
  echo "error: needs bash 4+ (macOS /bin/bash is 3.2); run through mise or install bash" >&2
  exit 1
fi

root="$(git rev-parse --show-toplevel)"
exec "$root/infra/rack-switch-fleet/fleet.sh" "$@"
