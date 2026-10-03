#!/usr/bin/env bash
#MISE description="Talk to the rack fleet's Omada controller: list, inform and adopt switches"
#
#   mise run rack:omada devices
#   mise run rack:omada inform ber1-mgmt
#   mise run rack:omada adopt ber1-mgmt
#
# The controller and its Open API client are management.controller in the site
# definition. See infra/rack-switch-fleet/AGENTS.md.

set -euo pipefail

root="$(git rev-parse --show-toplevel)"
exec "$root/infra/rack-switch-fleet/omada.sh" "$@"
