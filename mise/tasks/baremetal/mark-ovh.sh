#!/usr/bin/env bash
#MISE description="Set an OVH dedicated server's displayName so a CAPI fleet can adopt it"
#
# The OVHDedicatedMachine reconciler adopts a box whose service displayName starts
# with the fleet's adoptDisplayNamePrefix (the env boundary, since one OVH account
# holds every env's boxes). The operator only has to order the box and set that
# name; this scripts the rename instead of clicking through the manager.
#
# Usage:
#   OVH_APPLICATION_KEY=... OVH_APPLICATION_SECRET=... OVH_CONSUMER_KEY=... \
#     mise run baremetal:mark-ovh <service-name> <display-name>
#
# e.g. mise run baremetal:mark-ovh ns543284.ip-144-217-252.net tuist-kura-ovh-staging
#
# The token triple must be minted on the SAME OVH entity the box lives on, set via
# OVH_API_BASE (default ovh-us — the BHS box is on an OVHcloud US account):
#   ovh-us -> https://api.us.ovhcloud.com/1.0   (default)
#   ovh-ca -> https://ca.api.ovh.com/1.0
#   ovh-eu -> https://eu.api.ovh.com/1.0
# Pull the triple from 1Password:
#   export OVH_APPLICATION_KEY="$(op read 'op://tuist-k8s-staging/OVH_API/application-key')"
#   export OVH_APPLICATION_SECRET="$(op read 'op://tuist-k8s-staging/OVH_API/application-secret')"
#   export OVH_CONSUMER_KEY="$(op read 'op://tuist-k8s-staging/OVH_API/consumer-key')"
# The token needs GET /dedicated/server/*/serviceInfos and PUT /service/*.

set -euo pipefail

service="${1:-}"
display_name="${2:-}"

if [ -z "$service" ] || [ -z "$display_name" ]; then
  echo "usage: mise run baremetal:mark-ovh <service-name> <display-name>" >&2
  echo "  e.g. mise run baremetal:mark-ovh ns543284.ip-144-217-252.net tuist-kura-ovh-staging" >&2
  exit 2
fi
: "${OVH_APPLICATION_KEY:?set OVH_APPLICATION_KEY (op read 'op://tuist-k8s-staging/OVH_API/application-key')}"
: "${OVH_APPLICATION_SECRET:?set OVH_APPLICATION_SECRET}"
: "${OVH_CONSUMER_KEY:?set OVH_CONSUMER_KEY}"

base="${OVH_API_BASE:-https://api.us.ovhcloud.com/1.0}"

sha1hex() {
  if command -v sha1sum >/dev/null 2>&1; then sha1sum | awk '{print $1}'; else shasum -a 1 | awk '{print $1}'; fi
}

# OVH signs every call: X-Ovh-Signature = "$1$" + sha1(AS+CK+METHOD+URL+BODY+TS).
ovh() {
  local method="$1" path="$2" body="${3:-}"
  local url="${base}${path}"
  local ts sig
  ts="$(curl -fsS "${base}/auth/time")"
  # '$1$' is OVH's literal signature-scheme prefix, not a shell variable.
  # shellcheck disable=SC2016
  sig='$1$'"$(printf '%s+%s+%s+%s+%s+%s' \
    "$OVH_APPLICATION_SECRET" "$OVH_CONSUMER_KEY" "$method" "$url" "$body" "$ts" | sha1hex)"
  local args=(-fsS -X "$method" "$url"
    -H "X-Ovh-Application: ${OVH_APPLICATION_KEY}"
    -H "X-Ovh-Consumer: ${OVH_CONSUMER_KEY}"
    -H "X-Ovh-Timestamp: ${ts}"
    -H "X-Ovh-Signature: ${sig}")
  if [ -n "$body" ]; then
    args+=(-H "Content-Type: application/json" -d "$body")
  fi
  curl "${args[@]}"
}

service_id="$(ovh GET "/dedicated/server/${service}/serviceInfos" | grep -o '"serviceId":[0-9]*' | grep -o '[0-9]*' | head -1)"
[ -z "$service_id" ] && { echo "could not resolve serviceId for ${service} (check creds / OVH_API_BASE entity)" >&2; exit 1; }

# displayName lives on the service resource; OVH's /service/{id} API takes it
# nested under "resource", not flat (a flat {"displayName":...} 400s with
# "Some properties does not exist: displayName").
ovh PUT "/service/${service_id}" "{\"resource\":{\"displayName\":\"${display_name}\"}}" >/dev/null

echo "✓ OVH ${service} (service ${service_id}) displayName set to '${display_name}'"
