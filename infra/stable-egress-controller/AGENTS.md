# Stable Egress Controller

Owns active/standby election for the server's Hetzner Floating IP and gateway label. The host-configurer prepares every candidate; Cilium follows the single active label.

- Adopt a directly healthy, prepared active node, even outside the candidate pool. NodeReady alone must not demote a working gateway. Promote only Ready, schedulable, prepared standbys, deterministically when multiple candidates qualify.
- Require continuous direct Cilium health-check failure for 90 seconds or missing host preparation for five minutes before failover. Grace timestamps are leader-local: restart/handover restarts the grace rather than acting on stale evidence.
- Remove the old selector before moving the Floating IP; select the new gateway only after provider assignment succeeds. Clear stale cluster-wide active labels; steady state must not churn the address.
- Fail closed when the Floating IP is outside the configured egress-IP allowlist. Keep that allowlist aligned with the customer network guide.
- Preserve leader election for multiple replicas and eligibility-only Node event filtering. Host-configurer Pod changes also trigger reconciliation; kubelet heartbeats must not cause Cloud API polling storms.
- Deployment/RBAC is gated by `ciliumEgressGateway.server.failoverController.enabled` in [the platform template](../helm/platform/templates/stable-egress-controller.yaml). Release tag resolution belongs to [k8s:install-platform](../mise/tasks/k8s/install-platform.sh) (run with `mise -C infra` from the repository root), not a hard-coded chart tag.

## Configuration

| Flag | Default | Purpose |
|---|---|---|
| `--floating-ip-name` | (required) | Hetzner Cloud Floating IP to keep on the active node |
| `--egress-ip-allowlist` | (empty) | Comma-separated CIDRs of the documented egress set customers allowlist. When set, the controller **fails closed** if the Floating IP's address is outside it — so an un-allowlisted egress IP is never activated. Keep in lockstep with the customer network guide. |
| `--candidate-label` | `tuist.dev/stable-egress-candidate=server` | egress candidate pool selector |
| `--active-label` | `tuist.dev/stable-egress-gateway=server` | label placed on the single active node selected by Cilium |
| `--prepared-pod-label` | `tuist.dev/stable-egress-host-configurer=true` | Ready Pod label proving a candidate has the outbound address configured |
| `--prepared-pod-namespace` | `kube-system` | namespace containing the host-configurer Pods |
| `--node-health-port` | `9962` | Cilium host-network listener used to check node reachability independently from NodeReady |
| `--node-health-timeout` | `2s` | timeout for each direct node health check |
| `--node-unhealthy-grace-period` | `90s` | continuous failed-health duration required before failover |
| `--node-unprepared-grace-period` | `5m` | continuous missing host-preparation duration required before failover |
| `--hcloud-token-path` | `/etc/hcloud/token` | token file, mounted from `kube-system/hcloud` |
| `--resync-interval` | `30s` | periodic reconcile floor; Node eligibility changes and host-configurer Pod changes trigger reconciles in between. Kubelet status heartbeats are filtered out so the per-reconcile Hetzner read stays well under the API rate limit. |
| `--leader-elect` | `true` | required when `replicas > 1` |

## Tests

Run `go test ./...` here.

Covers `selectGateway` (sticky / failover / lexical / none), prepared-candidate
gating, `providerID` parsing, the egress-IP allowlist guard, the Node event
predicate (heartbeats dropped, eligibility changes let through), the
host-configurer Pod event predicate, and full reconcile (failover moves IP +
label, stale cluster-wide labels are stripped, steady state is no-op) against
controller-runtime's fake client + a fake Floating IP manager.

## Releasing

Wired into the standard component release flow (`mise/tasks/release/components.json`
+ `server-production-deployment.yml`), like the other infra controllers: a conventional commit scoped
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
`tuist_stable_egress_failovers_total`,
`tuist_stable_egress_gateway_node_healthy`, and
`tuist_stable_egress_health_check_failures_total` alongside controller-runtime
reconcile metrics. The platform chart annotates the metrics port for Alloy
discovery.
