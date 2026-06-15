# stable-egress-controller

Keeps the hosted Tuist server's **stable egress source IP** highly available.

## Purpose

Server pods SNAT their public egress through a single Hetzner Cloud Floating IP
(a stable address customers allowlist) via a `CiliumEgressGatewayPolicy`. That
policy routes through one gateway node, and the Floating IP can only be assigned
to one server at a time — so the gateway is inherently active/standby. This
controller makes the failover automatic.

It watches the egress **candidate** node pool and keeps exactly one Ready
candidate designated **active**: that node holds the Floating IP (Hetzner Cloud
API) and the active gateway label. On loss of the active node it re-elects
another candidate and moves both together. This replaces the manual
`hcloud floating-ip assign` + relabel runbook that caused a multi-hour egress
outage on 2026-06-14 when a hand-labelled gateway node was replaced.

## Architecture

```
 md-egress pool (≥2 nodes)            this controller (2 replicas, leader-elected)
 each self-labels at kubelet:          watches Nodes ──► elects 1 Ready candidate
   tuist.dev/stable-egress-                              │
     candidate=server                                    ├─► Hetzner API: assign Floating IP → active node
                                                          └─► label active node tuist.dev/stable-egress-gateway=server
                                                                         │
 CiliumEgressGatewayPolicy ──selects active label──────────────────────┘
 host-configurer DaemonSet ──selects active label──► configures eth0 on active node
```

Why not lean on Cilium: OSS Cilium egress gateway picks a gateway node by
lexical order with no health-based failover (cilium/cilium#30157; HA is an
Isovalent Enterprise feature) and has no concept of the Hetzner Floating IP,
which only moves via the Cloud API. The controller owns election + the IP + the
label; Cilium and the host-configurer just follow the label.

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
| `--active-label` | `tuist.dev/stable-egress-gateway=server` | label placed on the single active node (Cilium + host-configurer select on it) |
| `--hcloud-token-path` | `/etc/hcloud/token` | token file, mounted from `kube-system/hcloud` |
| `--resync-interval` | `30s` | periodic reconcile; Node events trigger reconciles in between |
| `--leader-elect` | `true` | required when `replicas > 1` |

## Tests

```bash
cd infra/stable-egress-controller
go test ./...
```

Covers `selectActive` (sticky / failover / lexical / none), `providerID`
parsing, the egress-IP allowlist guard, and full reconcile (failover moves IP +
label, stale cluster-wide labels are stripped, steady state is no-op) against
controller-runtime's fake client + a fake Floating IP manager.

## Releasing

Wired into the standard component release flow (`mise/tasks/release/components.json`
+ `release.yml`), like the other infra controllers: a conventional commit scoped
`…(stable-egress-controller)` touching `infra/stable-egress-controller/**`
triggers a `stable-egress-controller@<semver>` tag + a
`ghcr.io/tuist/tuist-stable-egress-controller:<semver>` image. Renovate then
bumps the platform chart pin (`failoverController.image.tag` in
`values-tuist.yaml`) and the chart deploy rolls it out. The
`stable-egress-controller-image.yml` workflow only builds `:sha-*`/`:latest` for
pre-release iteration.

Keep `failoverController.enabled: false` in prod until the image is released and
the tag pinned (the first `stable-egress-controller@0.1.0` release publishes it).

## Future work

- Emit a metric / Kubernetes Event when no Ready candidate exists, and alert on
  it (the silent gap that hid the original outage).
- Consider faster NotReady detection than the kubelet node-monitor grace period.
