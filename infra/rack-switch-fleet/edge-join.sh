#!/usr/bin/env bash
#
# Joins a rack's edge node to the cluster the rack belongs to, as a node that
# runs the rack's edge workloads and nothing else. The switches' path to the
# tailnet and their DHCP (infra/helm/rack-edge) then run there as pods.
#
# The node has to be on the tailnet first, since it advertises its tailnet
# address and the switches reach the controller through tailscale0. This
# installs Tailscale when it is missing; joining the tailnet is the one step
# that needs a person, and this says how.
#
#   mise run rack:edge-join --context <kube context> [--dry-run]
#   mise run rack:edge-join --context <kube context> --leave
#
# The join is kubeadm's, the way the cluster's own workers join: a bootstrap
# token good for an hour and used once, discovery pinned to the cluster CA's
# public key, and a kubelet client certificate for system:node:<name>, which
# kubeadm's bindings approve. It advertises the node's tailnet address, which
# is the only one of its addresses outside the cluster's pod CIDR.
#
# The Cilium agent must never run on this node: its networks sit inside the pod
# CIDR, and an agent would route them into the tunnel and cut the node off. So
# this refuses until the cluster's agent stays off nodes labelled
# cilium.io/no-schedule=true (infra/k8s/mgmt/bootstrap/cilium-values.yaml), and
# the node carries that label from its first registration. It gets a small
# local CNI configuration instead, in a range no cluster or rack network uses,
# so the kubelet reports it Ready; the edge workloads use host networking.
#
# See infra/rack-switch-fleet/AGENTS.md.

set -euo pipefail

FLEET_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
source "$FLEET_ROOT/lib/config.sh"
# shellcheck source-path=SCRIPTDIR
source "$FLEET_ROOT/lib/edge.sh"

SITE="${RACK_SITE:-ber1}"
context=""
dry_run=0
leave=0
while (( $# )); do
  case "$1" in
    --context) context="${2:-}"; shift 2;;
    --site) SITE="${2:-}"; shift 2;;
    --dry-run) dry_run=1; shift;;
    --leave) leave=1; shift;;
    *) echo "unknown argument: $1" >&2; exit 2;;
  esac
done

site_file="$(fleet_site_file "$SITE")"
[ -f "$site_file" ] || { echo "error: no site definition at $site_file" >&2; exit 2; }
[ -n "$context" ] || { echo "error: --context names the cluster the rack belongs to" >&2; exit 2; }
edge="$(jq -r '.management.edge.ssh // empty' "$site_file")"
[ -n "$edge" ] || { echo "error: $SITE has no management.edge.ssh" >&2; exit 2; }
node="${edge#*@}"
rack="$(jq -r '.site' "$site_file")"

# A range outside the pod CIDR (192.168.0.0/16), the service CIDR
# (10.128.0.0/12), the tailnet (100.64.0.0/10) and the rack's own segments.
local_cni_range="10.254.254.0/24"

kc() { kubectl --context "$context" "$@"; }
on_edge() { ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "$edge" "$1"; }

on_edge true 2>/dev/null || { echo "error: cannot reach $edge over SSH" >&2; exit 1; }

if (( leave )); then
  echo "taking $node out of $context"
  if (( ! dry_run )); then
    kc delete node "$node" --ignore-not-found
    on_edge "sudo -n kubeadm reset -f >/dev/null 2>&1 || true
      sudo -n rm -f /etc/cni/net.d/10-rack-edge.conflist
      sudo -n ip link delete cni-rackedge 2>/dev/null || true"
    echo "$node is no longer a node; the path its rack-edge pod installed stays until it reboots"
  fi
  exit 0
fi

# The rack-edge pod refuses the port too, but a wrong port in the site
# definition is better found before the node is part of anything.
interface="$(jq -r '.management.edge.interface // empty' "$site_file")"
if [ -n "$interface" ]; then
  fleet_edge_check "$site_file" || exit 2
  on_edge "ip link show dev $interface" >/dev/null 2>&1 || { echo "error: $node has no interface $interface (management.edge.interface)" >&2; exit 1; }
  if on_edge 'ip route show default' | awk '{for (i = 1; i < NF; i++) if ($i == "dev") print $(i + 1)}' | grep -qx -- "$interface"; then
    echo "error: $interface carries $node's default route; management.edge.interface names the switches' port" >&2
    exit 1
  fi
fi

# --- what the cluster has to guarantee first ---------------------------------

cilium_excludes="$(kc -n kube-system get daemonset cilium -o json | jq -r '
  [.spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[]?
   .matchExpressions[]? | select(.key == "cilium.io/no-schedule" and .operator == "NotIn" and (.values | index("true")))]
  | length > 0')"
if [ "$cilium_excludes" != true ]; then
  echo "error: the Cilium agent in $context would schedule onto $node. Its networks sit" >&2
  echo "       inside the pod CIDR and an agent would cut it off, so deploy the exclusion in" >&2
  echo "       infra/k8s/mgmt/bootstrap/cilium-values.yaml to this cluster first." >&2
  exit 1
fi
csi_excludes="$(kc -n kube-system get daemonset hcloud-csi-node -o json 2>/dev/null | jq -r '
  [.spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[]?
   .matchExpressions[]? | select(.key == "node.cluster.x-k8s.io/instance-type" and .operator == "NotIn" and (.values | index("rack")))]
  | length > 0' || echo absent)"
if [ "$csi_excludes" = false ]; then
  echo "note: hcloud-csi-node in $context does not exclude instance type rack yet, so it will"
  echo "      crash-loop on $node until infra/k8s/mgmt/bootstrap/hcloud-csi-values.yaml deploys."
fi

if [ "$(kc get node "$node" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = True ]; then
  echo "$node is already a Ready node of $context"
  exit 0
fi

# --- the tailnet ---------------------------------------------------------------

# Tailscale from its own apt repository, for the release Ubuntu reports.
if ! on_edge 'command -v tailscale' >/dev/null 2>&1; then
  if (( dry_run )); then
    echo "$node has no Tailscale; a run without --dry-run installs it, and the node then joins the tailnet"
    exit 0
  fi
  # shellcheck disable=SC2016  # expanded on the edge node
  on_edge '. /etc/os-release
    curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/$VERSION_CODENAME.noarmor.gpg" | sudo -n tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
    curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/$VERSION_CODENAME.tailscale-keyring.list" | sudo -n tee /etc/apt/sources.list.d/tailscale.list >/dev/null
    sudo -n apt-get update -qq && sudo -n DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tailscale >/dev/null'
  echo "installed tailscale on $node"
fi
if ! on_edge 'tailscale status --json 2>/dev/null' | jq -e '.BackendState == "Running"' >/dev/null 2>&1; then
  echo "error: $node is not on the tailnet yet. Joining is the one step that needs a person:" >&2
  echo "       infra/tailscale/acls.json must already carry tag:tuist-rack-edge, and the login" >&2
  echo "       URL this prints has to be opened by a tailnet admin:" >&2
  echo "         ssh -t $edge sudo tailscale up --hostname=$node --advertise-tags=tag:tuist-rack-edge" >&2
  echo "       Then disable key expiry for $node in the admin console, since it is a server," >&2
  echo "       and run this again." >&2
  exit 1
fi

version="$(kc version -o json 2>/dev/null | jq -r '.serverVersion.gitVersion')"
minor="$(cut -d. -f1-2 <<<"$version")"
tailnet_ip="$(on_edge 'tailscale ip -4' | head -1)"
[ -n "$tailnet_ip" ] || { echo "error: $node has no tailnet address" >&2; exit 1; }

cluster_kubeconfig="$(kc -n kube-public get configmap cluster-info -o jsonpath='{.data.kubeconfig}')"
endpoint="$(yq -r '.clusters[0].cluster.server' <<<"$cluster_kubeconfig" | sed 's|^https://||')"
ca_hash="sha256:$(yq -r '.clusters[0].cluster["certificate-authority-data"]' <<<"$cluster_kubeconfig" | base64 -d |
  openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -hex | awk '{print $NF}')"

echo "node          $node, advertising $tailnet_ip"
echo "cluster       $context ($version), API at $endpoint"
echo "labels        tuist.dev/rack-edge=$rack node.cluster.x-k8s.io/instance-type=rack cilium.io/no-schedule=true"
echo "taint         tuist.dev/rack-edge=$rack:NoSchedule"
echo "local CNI     $local_cni_range, for the kubelet's readiness only"
if (( dry_run )); then
  echo ""
  echo "dry run, nothing changed"
  exit 0
fi

# --- the node --------------------------------------------------------------

# containerd from Ubuntu, kubelet and kubeadm from the Kubernetes project's
# repository at the cluster's own version, and the kernel settings a kubelet
# needs. Swap is turned off, which the cluster's kubelet configuration expects.
# shellcheck disable=SC2016  # expanded on the edge node
on_edge "set -e
  sudo -n swapoff -a
  sudo -n sed -i -E 's|^([^#].*[[:space:]]swap[[:space:]].*)$|# \\1|' /etc/fstab
  printf 'overlay\nbr_netfilter\n' | sudo -n tee /etc/modules-load.d/rack-edge-kubelet.conf >/dev/null
  sudo -n modprobe overlay && sudo -n modprobe br_netfilter
  printf 'net.bridge.bridge-nf-call-iptables = 1\nnet.bridge.bridge-nf-call-ip6tables = 1\nnet.ipv4.ip_forward = 1\n' |
    sudo -n tee /etc/sysctl.d/90-rack-edge-kubelet.conf >/dev/null
  sudo -n sysctl -q --system
  sudo -n apt-get update -qq
  sudo -n DEBIAN_FRONTEND=noninteractive apt-get install -y -qq containerd apt-transport-https ca-certificates curl gpg >/dev/null
  sudo -n mkdir -p /etc/containerd /etc/apt/keyrings
  containerd config default | sed 's/SystemdCgroup = false/SystemdCgroup = true/' | sudo -n tee /etc/containerd/config.toml >/dev/null
  sudo -n systemctl restart containerd
  curl -fsSL https://pkgs.k8s.io/core:/stable:/$minor/deb/Release.key | sudo -n gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$minor/deb/ /' |
    sudo -n tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
  sudo -n apt-get update -qq
  package=\$(apt-cache madison kubelet | awk '{print \$3}' | grep -m1 '^${version#v}-')
  sudo -n apt-mark unhold kubelet kubeadm >/dev/null 2>&1 || true
  sudo -n DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --allow-change-held-packages kubelet=\$package kubeadm=\$package >/dev/null
  sudo -n apt-mark hold kubelet kubeadm >/dev/null
  sudo -n mkdir -p /etc/cni/net.d
  printf '%s\n' '{\"cniVersion\":\"1.0.0\",\"name\":\"rack-edge\",\"plugins\":[{\"type\":\"bridge\",\"bridge\":\"cni-rackedge\",\"isGateway\":true,\"ipMasq\":true,\"ipam\":{\"type\":\"host-local\",\"ranges\":[[{\"subnet\":\"$local_cni_range\"}]]}},{\"type\":\"portmap\",\"capabilities\":{\"portMappings\":true}}]}' |
    sudo -n tee /etc/cni/net.d/10-rack-edge.conflist >/dev/null"
echo "installed containerd and kubelet ${version#v} on $node"

# --- the join ------------------------------------------------------------------

token_id="$(openssl rand -hex 3)"
token_secret="$(openssl rand -hex 8)"
expiration="$(date -u -v+1H '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '+1 hour' '+%Y-%m-%dT%H:%M:%SZ')"
jq -n --arg id "$token_id" --arg secret "$token_secret" --arg expiration "$expiration" --arg node "$node" '{
  apiVersion: "v1", kind: "Secret", type: "bootstrap.kubernetes.io/token",
  metadata: {name: "bootstrap-token-\($id)", namespace: "kube-system"},
  stringData: {
    "token-id": $id, "token-secret": $secret, expiration: $expiration,
    description: "rack:edge-join for \($node), used once",
    "usage-bootstrap-authentication": "true", "usage-bootstrap-signing": "true",
    "auth-extra-groups": "system:bootstrappers:kubeadm:default-node-token"
  }
}' | kc apply -f - >/dev/null
trap 'kc -n kube-system delete secret "bootstrap-token-$token_id" --ignore-not-found >/dev/null' EXIT

# The configuration carries the token, so it reaches the edge node on stdin and
# is removed once kubeadm has read it.
cat <<CONFIG | on_edge "sudo -n mkdir -p /etc/kubernetes && sudo -n install -m 600 /dev/stdin /etc/kubernetes/rack-edge-join.yaml"
apiVersion: kubeadm.k8s.io/v1beta4
kind: JoinConfiguration
discovery:
  bootstrapToken:
    apiServerEndpoint: "$endpoint"
    token: "$token_id.$token_secret"
    caCertHashes: ["$ca_hash"]
nodeRegistration:
  name: "$node"
  criSocket: unix:///run/containerd/containerd.sock
  taints:
    - key: tuist.dev/rack-edge
      value: "$rack"
      effect: NoSchedule
  kubeletExtraArgs:
    - name: node-ip
      value: "$tailnet_ip"
    - name: node-labels
      value: "tuist.dev/rack-edge=$rack,node.cluster.x-k8s.io/instance-type=rack,cilium.io/no-schedule=true"
CONFIG
status=0
on_edge "sudo -n kubeadm join --config /etc/kubernetes/rack-edge-join.yaml >/tmp/rack-edge-join.log 2>&1" || status=$?
on_edge "sudo -n rm -f /etc/kubernetes/rack-edge-join.yaml"
if (( status )); then
  echo "error: kubeadm join failed on $node:" >&2
  on_edge 'tail -20 /tmp/rack-edge-join.log' | sed 's/^/       /' >&2
  exit 1
fi

for _ in $(seq 1 60); do
  [ "$(kc get node "$node" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = True ] && break
  sleep 5
done
kc get node "$node" -o wide
if kc get pods -A --field-selector "spec.nodeName=$node" -o json | jq -e '.items[] | select(.metadata.labels["k8s-app"] == "cilium")' >/dev/null; then
  echo "error: a Cilium agent was scheduled onto $node; take it out now with --leave" >&2
  exit 1
fi
echo "$node joined $context"
