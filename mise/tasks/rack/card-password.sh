#!/usr/bin/env bash
#MISE description="Print a rack PDU's or transfer switch's card password, derived from the root key in 1Password"
#
# The operator derives every rack power card's passwords from one root key
# (the 1Password item BER1_RACK_CARD_ROOT, field key). This derives the same
# password from the same item, for a person who needs a card's web UI. The
# root key goes from `op read` to the derivation on a pipe and is never
# printed.
#
# Usage:
#   mise run rack:card-password <device> [--role admin|controller] [--site ber1] [--vault <vault>]
#
# The vault defaults to the one the site's namespace syncs its secrets from:
# tuist-staging reads tuist-k8s-staging, and tuist, production's namespace,
# reads tuist-k8s-production. See "Rack card passwords" in
# infra/cluster-api-provider-tuist/AGENTS.md.

set -euo pipefail

root="$(git rev-parse --show-toplevel)"
device=""
role="admin"
site="ber1"
vault=""
item="BER1_RACK_CARD_ROOT"

while (( $# )); do
  case "$1" in
    --role) role="${2:-}"; shift 2;;
    --site) site="${2:-}"; shift 2;;
    --vault) vault="${2:-}"; shift 2;;
    --item) item="${2:-}"; shift 2;;
    -h|--help) sed -n '2,15p' "$0"; exit 0;;
    -*) echo "error: unknown option $1" >&2; exit 1;;
    *) device="$1"; shift;;
  esac
done

[ -n "$device" ] || { echo "error: name the device, e.g. ber1-pdu-b" >&2; exit 1; }
sites="$root/infra/rack-switch-fleet/sites"
[ -f "$sites/$site.json" ] || { echo "error: no site definition $sites/$site.json" >&2; exit 1; }

if [ -z "$vault" ]; then
  # shellcheck source=/dev/null
  source "$root/infra/rack-switch-fleet/lib/config.sh"
  env="$(fleet_site_env "$sites/$site.json")" || { echo "error: pass --vault" >&2; exit 1; }
  vault="tuist-k8s-$env"
fi

op read "op://$vault/$item/key" |
  (cd "$root/infra/cluster-api-provider-tuist" && go run ./cmd/rack-card-password --site "$site" --device "$device" --role "$role" --sites "$sites")
