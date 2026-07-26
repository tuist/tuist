# stable-egress-controller

Keeps the hosted Tuist server's **stable egress source IP** highly available.

## Purpose

Server pods SNAT their public egress through a single Hetzner Cloud Floating IP
(a stable address customers allowlist) via a `CiliumEgressGatewayPolicy`. That
policy routes through one gateway node, and the Floating IP can only be assigned
to one server at a time — so the gateway is inherently active/standby. This
controller makes the failover automatic.

It keeps one Ready node designated **active** — holding the Floating IP (Hetzner
Cloud API) and the active gateway label. It **adopts** whatever node already
holds the active label as long as that node is Ready (even one outside the
candidate pool), so it never disturbs a working gateway — enabling it over an
existing hand-configured gateway moves nothing (no Floating IP churn, no Cilium
reconvergence, no egress blip). Only when there is no healthy active node does it
fail over to a Ready candidate whose host-configurer Pod has reported Ready,
moving the IP + label together. This replaces the manual `hcloud floating-ip
assign` + relabel runbook
that caused a multi-hour egress outage on 2026-06-14 when a hand-labelled gateway
node was replaced.

## Architecture

```
 md-egress pool (≥2 nodes)            this controller (2 replicas, leader-elected)
 each self-labels at kubelet:          watches Nodes ──► elects 1 Ready candidate
   tuist.dev/stable-egress-                              │
     candidate=server       host-configurer prepares IP ──┤
                                and reports Pod Ready      ├─► Hetzner API: assign Floating IP → active node
                                                          └─► label prepared node tuist.dev/stable-egress-gateway=server
                                                                         │
 CiliumEgressGatewayPolicy ──selects active label──────────────────────┘
 host-configurer DaemonSet ──selects candidate label──► preconfigures every standby
```

Why not lean on Cilium: OSS Cilium egress gateway picks a gateway node by
lexical order with no health-based failover (cilium/cilium#30157; HA is an
Isovalent Enterprise feature) and has no concept of the Hetzner Floating IP,
which only moves via the Cloud API. The controller owns election + the IP + the
label; Cilium follows the active label after the host-configurer has prepared
the candidate.

## Module layout

- `cmd/manager/main.go` — flags, controller-runtime manager, leader election.
- `controllers/failover.go` — the reconciler; `selectActive` is the pure
  election policy (sticky to a healthy current node, else lexically-lowest).
- `internal/hcloud/` — Hetzner Cloud SDK wrapper implementing `FloatingIPManager`.
- `config/rbac/role.yaml` — hand-written RBAC (nodes patch + leases + events).

The Deployment + RBAC are rendered by the platform Helm chart
(`infra/helm/platform/templates/stable-egress-controller.yaml`), gated on
`ciliumEgressGateway.server.failoverController.enabled`.

## Configuration

| Flag | Default | Purpose |
|---|---|---|
| `--floating-ip-name` | (required) | Hetzner Cloud Floating IP to keep on the active node |
| `--egress-ip-allowlist` | (empty) | Comma-separated CIDRs of the documented egress set customers allowlist. When set, the controller **fails closed** if the Floating IP's address is outside it — so an un-allowlisted egress IP is never activated. Keep in lockstep with the customer network guide. |
| `--candidate-label` | `tuist.dev/stable-egress-candidate=server` | egress candidate pool selector |
| `--active-label` | `tuist.dev/stable-egress-gateway=server` | label placed on the single active node selected by Cilium |
| `--prepared-pod-label` | `tuist.dev/stable-egress-host-configurer=true` | Ready Pod label proving a candidate has the outbound address configured |
| `--prepared-pod-namespace` | `kube-system` | namespace containing the host-configurer Pods |
| `--hcloud-token-path` | `/etc/hcloud/token` | token file, mounted from `kube-system/hcloud` |
| `--resync-interval` | `30s` | periodic reconcile floor; Node eligibility changes and host-configurer Pod changes trigger reconciles in between. Kubelet status heartbeats are filtered out so the per-reconcile Hetzner read stays well under the API rate limit. |
| `--leader-elect` | `true` | required when `replicas > 1` |

## Tests

```bash
cd infra/stable-egress-controller
go test ./...
```

Covers `selectGateway` (sticky / failover / lexical / none), prepared-candidate
gating, `providerID` parsing, the egress-IP allowlist guard, the Node event
predicate (heartbeats dropped, eligibility changes let through), the
host-configurer Pod event predicate, and full reconcile (failover moves IP +
label, stale cluster-wide labels are stripped, steady state is no-op) against
controller-runtime's fake client + a fake Floating IP manager.

## Releasing

Wired into the standard component release flow (`mise/tasks/release/components.json`
+ `release.yml`), like the other infra controllers: a conventional commit scoped
`…(stable-egress-controller)` touching `infra/stable-egress-controller/**`
triggers a `stable-egress-controller@<semver>` tag + a
`ghcr.io/tuist/tuist-stable-egress-controller:<semver>` image. The deployed tag
is **resolved at deploy time** by `k8s:install-platform` — the highest
`stable-egress-controller@<semver>` reachable from the deployed commit, `--set`
onto the platform chart (same pattern as the fleet/runtime images, see
`server-deployment.yml`'s resolve step). No tag is pinned in the chart values.
The `stable-egress-controller-image.yml` workflow only builds `:sha-*`/`:latest`
for pre-release iteration.

Keep `failoverController.enabled: false` in prod until the image is released
(the first `stable-egress-controller@0.1.0` release publishes it).

## Metrics

The controller exposes `tuist_stable_egress_gateway_available`,
`tuist_stable_egress_gateway_prepared`,
`tuist_stable_egress_gateway_active`, and
`tuist_stable_egress_failovers_total` alongside controller-runtime reconcile
metrics. The platform chart annotates the metrics port for Alloy discovery.
