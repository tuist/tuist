#!/usr/bin/env bash
#MISE description="Reconcile the management cluster's Hetzner Cloud network and API load balancer with infra/k8s/mgmt/talos/hetzner.yaml. Prints the changes; pass --apply to make them."
#USAGE flag "--apply" help="Make the changes instead of only printing them"

# Needs HCLOUD_TOKEN for project tuist-mgmt.
#
# Reconciles: the network and its subnet, each node's attachment to the
# network at its declared private IP, a primary IPv4 named after the load
# balancer (so the endpoint address survives a load balancer recreate), the
# load balancer's type, network attachment, TCP services and server targets,
# and delete protection on the network, primary IP and load balancer.
#
# The only thing it removes is a load balancer target whose server is not
# listed under `nodes`. It refuses to leave the load balancer without a
# target: a target is never pruned or re-added if it is the last one.
# Settings Hetzner cannot change in place (a network's IP range, a node's
# private IP, a load balancer's location or public IP) fail the run instead
# of being recreated.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SPEC="$REPO_ROOT/infra/k8s/mgmt/talos/hetzner.yaml"
LABEL="managed-by=mgmt-cluster-apply"

apply=false
if [[ "${1:-}" == "--apply" ]]; then
  apply=true
fi

: "${HCLOUD_TOKEN:?HCLOUD_TOKEN must be set to a token for Hetzner Cloud project tuist-mgmt}"

fail() {
  echo "error: $*" >&2
  exit 1
}

yq -e '
  (.location | tag == "!!str") and
  (.network.name | tag == "!!str") and
  (.network.ipRange | tag == "!!str") and
  (.network.subnet | tag == "!!str") and
  (.loadBalancer.name | tag == "!!str") and
  (.loadBalancer.type | tag == "!!str") and
  (.loadBalancer.usePrivateIP | tag == "!!bool") and
  (.loadBalancer.ports | (tag == "!!seq" and length > 0 and all_c(tag == "!!int"))) and
  (.nodes | (tag == "!!seq" and length > 0 and all_c((.name | tag == "!!str") and (.privateIP | tag == "!!str"))))
' "$SPEC" >/dev/null || fail "$SPEC is missing a field or has one of the wrong type"

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
read -r -a nodes <<<"$(spec '[.nodes[].name] | join(" ")')"
read -r -a node_ips <<<"$(spec '[.nodes[].privateIP] | join(" ")')"

network_zone="$(hcloud location describe "$location" -o json | jq -r .network_zone)"

find_network() { hcloud network list -o json | jq --arg n "$network_name" '.[] | select(.name == $n)'; }
find_lb() { hcloud load-balancer list -o json | jq --arg n "$lb_name" '.[] | select(.name == $n)'; }

echo "==> Network $network_name"
network="$(find_network)"
if [[ -z "$network" ]]; then
  change network create --name "$network_name" --ip-range "$network_range" \
    --label "$LABEL" --enable-protection delete
  if $apply; then network="$(find_network)"; fi
elif [[ "$(jq -r .ip_range <<<"$network")" != "$network_range" ]]; then
  fail "network $network_name has IP range $(jq -r .ip_range <<<"$network"), the spec says $network_range; Hetzner cannot change it in place"
elif [[ "$(jq -r .protection.delete <<<"$network")" != "true" ]]; then
  change network enable-protection "$network_name" delete
fi
if [[ -z "$network" ]] || ! jq -e --arg r "$subnet_range" 'any(.subnets[]; .ip_range == $r)' <<<"$network" >/dev/null; then
  change network add-subnet "$network_name" --type cloud --network-zone "$network_zone" --ip-range "$subnet_range"
fi
network_id="$(jq -r '.id // empty' <<<"${network:-null}")"

echo "==> Servers"
for i in "${!nodes[@]}"; do
  node="${nodes[$i]}"
  node_ip="${node_ips[$i]}"
  attached_ip="$(hcloud server describe "$node" -o json |
    jq -r --argjson id "${network_id:-0}" '.private_net[]? | select(.network == $id) | .ip')"
  if [[ -z "$attached_ip" ]]; then
    change server attach-to-network "$node" --network "$network_name" --ip "$node_ip"
  elif [[ "$attached_ip" != "$node_ip" ]]; then
    fail "server $node is attached to network $network_name as $attached_ip, the spec says $node_ip; Hetzner cannot change it in place"
  fi
done

echo "==> Primary IPv4 $lb_name"
primary_ip="$(hcloud primary-ip list -o json | jq --arg n "$lb_name" '.[] | select(.name == $n and .type == "ipv4")')"
if [[ -z "$primary_ip" ]]; then
  change primary-ip create --type ipv4 --name "$lb_name" --location "$location" \
    --label "$LABEL" --enable-protection delete
elif [[ "$(jq -r .protection.delete <<<"$primary_ip")" != "true" ]]; then
  change primary-ip enable-protection "$lb_name" delete
fi

echo "==> Load balancer $lb_name"
lb="$(find_lb)"
if [[ -z "$lb" ]]; then
  change load-balancer create --name "$lb_name" --type "$lb_type" --location "$location" \
    --network "$network_name" --primary-ipv4 "$lb_name" --label "$LABEL" --enable-protection delete
else
  if [[ "$(jq -r .location.name <<<"$lb")" != "$location" ]]; then
    fail "load balancer $lb_name is in $(jq -r .location.name <<<"$lb"), the spec says $location; Hetzner cannot move it"
  fi
  if [[ -n "$primary_ip" && "$(jq -r .public_net.ipv4.ip <<<"$lb")" != "$(jq -r .ip <<<"$primary_ip")" ]]; then
    fail "load balancer $lb_name does not use primary IPv4 $lb_name ($(jq -r .ip <<<"$primary_ip")); Hetzner assigns it only at creation"
  fi
  if [[ "$(jq -r .load_balancer_type.name <<<"$lb")" != "$lb_type" ]]; then
    change load-balancer change-type "$lb_name" "$lb_type"
  fi
  if [[ "$(jq -r .protection.delete <<<"$lb")" != "true" ]]; then
    change load-balancer enable-protection "$lb_name" delete
  fi
  if [[ -z "$network_id" ]] || ! jq -e --argjson id "$network_id" 'any(.private_net[]; .network == $id)' <<<"$lb" >/dev/null; then
    change load-balancer attach-to-network "$lb_name" --network "$network_name"
  fi
fi

for port in "${lb_ports[@]}"; do
  service="$(jq --argjson p "$port" '.services[]? | select(.listen_port == $p)' <<<"${lb:-null}")"
  if [[ -z "$service" ]]; then
    change load-balancer add-service "$lb_name" --protocol tcp --listen-port "$port" --destination-port "$port"
  elif [[ "$(jq -r '"\(.protocol) \(.destination_port)"' <<<"$service")" != "tcp $port" ]]; then
    change load-balancer update-service "$lb_name" --listen-port "$port" --protocol tcp --destination-port "$port"
  fi
done

target_count="$(jq '[.targets[]? | select(.type == "server")] | length' <<<"${lb:-null}")"
wanted_ids=()
for node in "${nodes[@]}"; do
  server="$(hcloud server describe "$node" -o json)"
  server_id="$(jq -r .id <<<"$server")"
  wanted_ids+=("$server_id")
  target="$(jq --argjson id "$server_id" '.targets[]? | select(.type == "server" and .server.id == $id)' <<<"${lb:-null}")"

  if [[ "$use_private_ip" == "true" ]] && { [[ -z "$network_id" ]] || ! jq -e --argjson id "$network_id" 'any(.private_net[]; .network == $id)' <<<"$server" >/dev/null; }; then
    fail "server $node is not attached to network $network_name, so the load balancer cannot reach its private IP"
  fi

  if [[ -n "$target" && "$(jq -r .use_private_ip <<<"$target")" != "$use_private_ip" ]]; then
    if (( target_count <= 1 )); then
      fail "switching $node to use_private_ip=$use_private_ip means removing the load balancer's only target; add another node first"
    fi
    change load-balancer remove-target "$lb_name" --server "$node"
    target=""
    target_count=$((target_count - 1))
  fi
  if [[ -z "$target" ]]; then
    change load-balancer add-target "$lb_name" --server "$node" --use-private-ip="$use_private_ip"
    target_count=$((target_count + 1))
  fi
done

if [[ -n "$lb" ]]; then
  keep="$(printf '%s\n' "${wanted_ids[@]}" | jq -s .)"
  stale_ids="$(jq -r --argjson keep "$keep" '.targets[]? | select(.type == "server" and (.server.id | IN($keep[]) | not)) | .server.id' <<<"$lb")"
  for stale_id in $stale_ids; do
    if (( target_count <= 1 )); then
      fail "refusing to remove target server $stale_id: it would leave the load balancer without targets"
    fi
    change load-balancer remove-target "$lb_name" --server "$stale_id"
    target_count=$((target_count - 1))
  done
fi

if $apply; then
  echo "==> $lb_name public IPv4: $(hcloud load-balancer describe "$lb_name" -o json | jq -r .public_net.ipv4.ip)"
else
  echo "==> Dry run; pass --apply to make these changes"
fi
