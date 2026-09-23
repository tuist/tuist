#!/usr/bin/env bash
# Resolves a rack Linux host from the chart values its RackLinuxHost is
# rendered from, so the stick and the operator agree on it.
# Sourced: rack_host_json <env> <host>

rack_host_json() {
  local env="$1" host="$2" root values fleet entry
  root="$(git rev-parse --show-toplevel)"
  values="$root/infra/helm/tuist/values-managed-$env.yaml"
  if [ ! -f "$values" ]; then
    echo "error: no values for env '$env' at $values" >&2
    return 2
  fi
  fleet="$(yq -o=json '.rackLinuxFleet // {}' "$values")"
  if [ "$(jq -r '.enabled // false' <<<"$fleet")" != true ]; then
    echo "error: rackLinuxFleet is not enabled in $values" >&2
    return 2
  fi
  entry="$(jq -c --arg h "$host" '(.hosts // [])[] | select(.name == $h)' <<<"$fleet")"
  if [ -z "$entry" ]; then
    echo "error: $host is not in rackLinuxFleet.hosts in $values" >&2
    echo "known hosts: $(jq -r '[(.hosts // [])[].name] | join(", ")' <<<"$fleet")" >&2
    return 2
  fi
  jq -n --argjson fleet "$fleet" --argjson host "$entry" --arg env "$env" '{
    name: $host.name,
    role: $host.role,
    sshUser: ($host.sshUser // $fleet.sshUser // "tuist"),
    tailnetTags: ($host.tailnetTags // []),
    vault: ("tuist-k8s-" + $env),
    sshItem: ($fleet.sshExternalSecret.item // ""),
    tailscaleItem: ($fleet.tailscale.externalSecret.item // "")
  }'
}
