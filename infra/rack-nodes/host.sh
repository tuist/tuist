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
  entry="$(jq -c --arg h "$host" '(.hosts // [])[] | select(.hostname == $h or ((.uuid // "") | ascii_downcase) == ($h | ascii_downcase))' <<<"$fleet")"
  if [ -z "$entry" ]; then
    echo "error: $host is not in rackLinuxFleet.hosts in $values" >&2
    echo "known hosts: $(jq -r '[(.hosts // [])[].hostname] | join(", ")' <<<"$fleet")" >&2
    return 2
  fi
  jq -n --argjson fleet "$fleet" --argjson host "$entry" --arg env "$env" '{
    name: $host.hostname,
    role: $host.role,
    sshUser: ($host.sshUser // $fleet.sshUser // "tuist"),
    tailnetTags: ($host.tailnetTags // $fleet.roles[$host.role].tailnetTags // $fleet.tailnetTags // []),
    vault: ("tuist-k8s-" + $env),
    sshItem: ($fleet.sshExternalSecret.item // ""),
    tailscaleItem: ($fleet.tailscale.externalSecret.item // "")
  }'
}

# The env's rack boot server, as a stick's installer reaches it: the site's
# provisioning address, which the edge holding it serves on.
# Sourced: rack_boot_server <env>
rack_boot_server() {
  local env="$1" root values address port
  root="$(git rev-parse --show-toplevel)"
  values="$root/infra/helm/tuist/values-managed-$env.yaml"
  if [ ! -f "$values" ]; then
    echo "error: no values for env '$env' at $values" >&2
    return 2
  fi
  address="$(yq -r '.rackLinuxFleet.boot.address // ""' "$values")"
  if [ -z "$address" ]; then
    echo "error: $values sets no rackLinuxFleet.boot.address, so $env has no boot server" >&2
    return 2
  fi
  port="$(yq -r '.rackLinuxFleet.boot.httpPort // ""' "$values")"
  [ -n "$port" ] || port="$(yq -r '.rackLinuxFleet.boot.httpPort' "$root/infra/helm/tuist/values.yaml")"
  echo "http://$address:$port"
}
