#!/usr/bin/env bash
#MISE description="Reconcile the management cluster's Hetzner Cloud network and API load balancer with infra/k8s/mgmt/talos/hetzner.yaml. Prints the changes; pass --apply to make them."
#USAGE flag "--apply" help="Make the changes instead of only printing them"

# Needs HCLOUD_TOKEN for project tuist-mgmt. Creates what is missing and
# fixes what drifted. The only thing it removes is a load balancer target
# whose server is not listed under `nodes`. Settings Hetzner cannot change
# in place (a network's IP range, a load balancer's location) fail the run
# instead of being recreated.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SPEC="$REPO_ROOT/infra/k8s/mgmt/talos/hetzner.yaml"
LABEL="managed-by=mgmt-cluster-apply"

apply=false
if [[ "${1:-}" == "--apply" ]]; then
  apply=true
fi

: "${HCLOUD_TOKEN:?HCLOUD_TOKEN must be set to a token for Hetzner Cloud project tuist-mgmt}"

spec() { yq -r "$1" "$SPEC"; }

change() {
  echo "+ hcloud $*"
  if $apply; then
    hcloud "$@"
  fi
}

location="$(spec .location)"
network_name="$(spec .network.name)"
network_range="$(spec .network.ipRange)"
subnet_range="$(spec .network.subnet)"
lb_name="$(spec .loadBalancer.name)"
lb_type="$(spec .loadBalancer.type)"
use_private_ip="$(spec .loadBalancer.usePrivateIP)"
read -r -a lb_ports <<<"$(spec '.loadBalancer.ports | join(" ")')"
read -r -a nodes <<<"$(spec '.nodes | join(" ")')"

network_zone="$(hcloud location describe "$location" -o json | jq -r .network_zone)"

echo "==> Network $network_name"
network="$(hcloud network list -o json | jq --arg n "$network_name" '.[] | select(.name == $n)')"
if [[ -z "$network" ]]; then
  change network create --name "$network_name" --ip-range "$network_range" \
    --label "$LABEL" --enable-protection delete
elif [[ "$(jq -r .ip_range <<<"$network")" != "$network_range" ]]; then
  echo "error: network $network_name has IP range $(jq -r .ip_range <<<"$network"), the spec says $network_range; Hetzner cannot change it in place" >&2
  exit 1
fi
if [[ -z "$network" ]] || ! jq -e --arg r "$subnet_range" 'any(.subnets[]; .ip_range == $r)' <<<"$network" >/dev/null; then
  change network add-subnet "$network_name" --type cloud --network-zone "$network_zone" --ip-range "$subnet_range"
fi

echo "==> Load balancer $lb_name"
lb="$(hcloud load-balancer list -o json | jq --arg n "$lb_name" '.[] | select(.name == $n)')"
if [[ -z "$lb" ]]; then
  change load-balancer create --name "$lb_name" --type "$lb_type" --location "$location" \
    --network "$network_name" --label "$LABEL" --enable-protection delete
else
  if [[ "$(jq -r .location.name <<<"$lb")" != "$location" ]]; then
    echo "error: load balancer $lb_name is in $(jq -r .location.name <<<"$lb"), the spec says $location; Hetzner cannot move it" >&2
    exit 1
  fi
  if [[ "$(jq -r .load_balancer_type.name <<<"$lb")" != "$lb_type" ]]; then
    change load-balancer change-type "$lb_name" "$lb_type"
  fi
  network_id="$(jq -r .id <<<"$network")"
  if [[ -n "$network" ]] && ! jq -e --argjson id "$network_id" 'any(.private_net[]; .network == $id)' <<<"$lb" >/dev/null; then
    change load-balancer attach-to-network "$lb_name" --network "$network_name"
  fi
fi

for port in "${lb_ports[@]}"; do
  if [[ -z "$lb" ]] || ! jq -e --argjson p "$port" 'any(.services[]; .listen_port == $p)' <<<"$lb" >/dev/null; then
    change load-balancer add-service "$lb_name" --protocol tcp --listen-port "$port" --destination-port "$port"
  fi
done

for node in "${nodes[@]}"; do
  server_id="$(hcloud server describe "$node" -o json | jq -r .id)"
  target="$(jq --argjson id "$server_id" '.targets[]? | select(.type == "server" and .server.id == $id)' <<<"${lb:-null}")"
  if [[ -n "$target" && "$(jq -r .use_private_ip <<<"$target")" != "$use_private_ip" ]]; then
    change load-balancer remove-target "$lb_name" --server "$node"
    target=""
  fi
  if [[ -z "$target" ]]; then
    change load-balancer add-target "$lb_name" --server "$node" --use-private-ip="$use_private_ip"
  fi
done

if [[ -n "$lb" ]]; then
  wanted_ids="$(for node in "${nodes[@]}"; do hcloud server describe "$node" -o json | jq .id; done | jq -s .)"
  while read -r stale_id; do
    [[ -z "$stale_id" ]] && continue
    change load-balancer remove-target "$lb_name" --server "$(hcloud server describe "$stale_id" -o json | jq -r .name)"
  done < <(jq -r --argjson keep "$wanted_ids" '.targets[]? | select(.type == "server" and (.server.id | IN($keep[]) | not)) | .server.id' <<<"$lb")
fi

if $apply; then
  ipv4="$(hcloud load-balancer describe "$lb_name" -o json | jq -r .public_net.ipv4.ip)"
  echo "==> $lb_name public IPv4: $ipv4"
else
  echo "==> Dry run; pass --apply to make these changes"
fi
