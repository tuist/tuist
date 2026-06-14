# Tuist Platform Helm Chart

Platform-level Helm umbrella chart installed **once per Kubernetes cluster** that hosts the Tuist-managed deployment. It bundles the infrastructure that our per-app chart (`infra/helm/tuist/`) assumes is already running.

## What's in it

| Component | Purpose |
|---|---|
| `cert-manager` | TLS certificate issuance via Let's Encrypt + Cloudflare DNS-01 |
| `ingress-nginx` | Ingress controller backed by a cloud LoadBalancer |
| `kura-*-ingress-nginx` | Optional region-local Kura ingress controllers backed by shared regional cloud LoadBalancers |
| `external-dns` | Sync Ingress / Service hostnames into Cloudflare DNS |
| `external-secrets` | Pull secrets from external stores (1Password, SOPS, etc.) into the cluster |
| `metrics-server` | Resource metrics API (`pods.metrics.k8s.io`) consumed by HPAs and `kubectl top` |
| `ClusterIssuer` | Shared Let's Encrypt issuer wired to Cloudflare DNS-01 |
| `CiliumEgressGatewayPolicy` | Optional stable outbound source IP for hosted Tuist server traffic |

## Bootstrap

```bash
# 1. Create the target namespace.
kubectl create namespace platform

# 2. Create the Cloudflare API token Secret out-of-band. The token must have
#    Zone.DNS:Edit scope on the managed zone(s). Never commit this value.
kubectl -n platform create secret generic cloudflare-api-token \
  --from-literal=api-token="$CLOUDFLARE_API_TOKEN"

# 3. Fetch chart dependencies.
helm dependency update infra/helm/platform

# 4. Install the platform with the right provider overlay.
helm upgrade --install platform infra/helm/platform \
  -n platform \
  -f infra/helm/platform/values-hetzner.yaml
```

Other clouds can plug in by adding a `values-<provider>.yaml` overlay that
sets the provider-specific LoadBalancer annotations + any LB-specific
ingress-nginx config. The production `values-tuist.yaml` overlay also enables
three Kura-specific ingress-nginx aliases (`kura-eu-central`, `kura-us-east`,
`kura-us-west`) so cache artifact traffic has dedicated regional gateways
instead of sharing the main Tuist web ingress dataplane.
Customer-dedicated Kura gateways are intentionally not chart aliases here:
the Tuist server emits opaque `KuraGateway` resources and the Kura controller
reconciles the dedicated ingress-nginx + LoadBalancer lifecycle.

`k8s:install-platform` also loads `values-<cluster-name>.yaml` when present.
Use that cluster overlay for static environment configuration such as stable
egress IPs and managed-cluster LoadBalancer locations.

## Local validation

```bash
helm dependency update infra/helm/platform
helm template platform infra/helm/platform | kubectl apply --dry-run=client -f -
helm lint infra/helm/platform
```

## Stable Server Egress

Server pods use a Cilium egress gateway so customer-facing outbound traffic
leaves from a stable environment-specific address. These addresses are Hetzner
Floating IPs in the `tuist-workloads` project.

| Cluster | Namespace | Egress IP | HCloud resource | Host configurer | Status |
|---|---|---|---|---|---|
| `tuist-staging` | `tuist-staging` | `78.47.186.71` | Floating IP `tuist-staging-server-egress` | Enabled | Active and verified |
| `tuist-canary` | `tuist-canary` | `78.47.174.50` | Floating IP `tuist-canary-server-egress` | Enabled | Active and verified |
| `tuist` | `tuist` | `116.202.0.10` | Floating IP `tuist-production-server-egress` | Enabled | Active and verified |

When enabled, a `values-<cluster-name>.yaml` overlay renders:

- `CiliumEgressGatewayPolicy/tuist-server-stable-egress`, which selects server
  pods in the configured namespace and SNATs public-internet traffic to the
  configured egress IP via the node carrying the **active** label
  `tuist.dev/stable-egress-gateway=server`.
- `DaemonSet/kube-system/tuist-server-stable-egress-host-configurer`, which runs
  on the active node and keeps the Floating IP + source route present on its
  `eth0`.
- When `failoverController.enabled`, the
  `Deployment/kube-system/stable-egress-controller` (see
  [`infra/stable-egress-controller/`](../../stable-egress-controller/)).

### HA failover (no single point of failure)

The gateway runs **active/standby across a dedicated ≥2-node egress pool**, with
automatic failover — no manual steps and no SPOF:

- **Candidate pool:** the `md-egress` pool (`cluster-production.yaml`,
  `replicas: 2`) self-applies `tuist.dev/stable-egress-candidate=server` via the
  ClusterClass `workerNodeLabels` variable. kubelet sets it at registration, so
  it survives MachineHealthCheck remediation (CAPI's metadata-label sync would
  not — it only passes node-role/node-restriction/node.cluster prefixes).
- **Election + IP:** the stable-egress controller (leader-elected, 2 replicas)
  picks one Ready candidate as active and keeps the Hetzner Floating IP (Cloud
  API) **and** the active `tuist.dev/stable-egress-gateway` label on it. On loss
  of the active node it re-elects the other candidate and moves both together
  (~30–60s: node-NotReady detection + reassign; faster on node deletion).
- **Datapath:** Cilium re-selects the gateway (1s reconcile) and the
  host-configurer reschedules onto the new active node automatically.

Why Cilium alone isn't enough: our Cilium 1.18 OSS egress gateway selects a
gateway node by lexical order with no health-based failover (cilium/cilium#30157
— HA is Enterprise), and it has no concept of the Hetzner Floating IP, which
must be reassigned via the Cloud API. The controller owns both.

> Background: a 2026-06-14 production outage traced to this binding being a
> single hand-labelled general worker. It got remediated; neither the label nor
> the Floating IP migrated, so all server egress black-holed and the server
> crash-looped on its first outbound call. The HA pool + controller remove both
> the SPOF and the manual runbook.

### Manual failover (fallback)

Only needed if the controller is disabled or unavailable mid-incident:

```bash
export KUBECONFIG=~/.kube/tuist-production.yaml
export FLOATING_IP_NAME=tuist-production-server-egress
export NEW_NODE=<a-ready-md-egress-node>

# Move the cloud route in Hetzner, then the active label; the host-configurer
# follows the label and Cilium re-selects within ~1s.
hcloud floating-ip assign "$FLOATING_IP_NAME" "$NEW_NODE"
kubectl label node "$NEW_NODE" tuist.dev/stable-egress-gateway=server --overwrite

# Verify from any server pod (should print the configured egress IP).
kubectl -n tuist exec deploy/tuist-tuist-server -- curl -fsS https://api.ipify.org
```

## Notes

- The main ingress-nginx LoadBalancer is annotated for Hetzner Cloud (Nuremberg region) by default. Managed Tuist cluster overlays pin it explicitly to `fsn1`, matching the general worker pools; regional Kura LoadBalancers are pinned separately.
- Production Kura ingress controllers are shared per region by default. Their LoadBalancers are placed in `fsn1`, `ash`, and `hil` and their pods are pinned to the matching Kura node pools. Customer-dedicated gateways are server-driven `KuraGateway` resources with opaque names, not customer-specific Helm values.
- external-dns is scoped by `txtOwnerId: tuist-platform` — one cluster, one TXT prefix. Run it with `policy: sync` only if you're happy with it deleting DNS records that aren't tracked by any Ingress.
- cert-manager CRDs are installed by the subchart (`installCRDs: true`). If another tool manages them, turn that off.
