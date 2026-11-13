# OpenObserve shadow deployment

This standalone wrapper pins upstream OpenObserve chart 1.1.4 and the OSS
v1.1.2 image. It is a parallel evaluation backend, not a Grafana Cloud cutover.
No collector configuration, dashboard, alert binding or public ingress changes
with its installation. The CI rollout is staging first, then optionally canary;
it has no production deployment job. These files are desired state, not evidence
of a successful deployment or production query parity.

## Storage and credentials

Each environment overlay reuses that environment's existing Tigris S3-compatible
bucket under **`openobserve/`**, never Pulse's `tenants/` or `system/` objects.
Existing Pulse history cannot be queried or imported just by sharing a bucket.
Both systems write separate copies. A prefix separates object names, not IAM
permissions or bucket-wide lifecycle rules. Confirm no bucket-wide expiry or
cleanup can affect either backend. Separate bucket-scoped credentials are the
preferred stronger boundary when the provider cannot scope access by prefix.
Do not enable this shared-bucket configuration without that review.

CI generates independent random root and internal gRPC credentials in the
`openobserve-auth` Secret on first installation. Subsequent runs preserve it;
CI never retrieves or prints its values. Do not delete or rotate it as rollout
recovery. Include it in the operator's recovery plan before a real cutover.
The root account is `openobserve@tuist.dev`, with the initial `default` organization.
Root authentication is only for this isolated evaluation; create separate
ingestion and read identities before wiring sustained collector traffic.

Existing `PULSE_S3_CREDENTIALS/{access_key_id,secret_access_key}` items in each
environment's own ESO vault are mapped to `openobserve-credentials`. No new
1Password items are needed, no agent reads them, and no Pulse authentication
token is reused. CNPG generates the
non-superuser metadata application credential; pods reference its `uri` directly.
S3 contains telemetry, **not a substitute for PostgreSQL metadata or ingester WAL**.
NATS has three persistent replicas. Ingester WAL, query cache and scheduler state
also have PVCs. Staging requests 36 GiB total with one metadata instance; canary
requests 41 GiB with two metadata instances. Both use a single ingester, querier
and router to keep the pilot small; neither establishes backend HA. The unused
production candidate requests 200 GiB. Inspect headroom and provider costs before apply.
No metadata backup is configured yet: backup/restore testing is a cutover gate.

Retention is disabled (`ZO_COMPACT_DATA_RETENTION_DAYS=0`) for the initial shadow
evaluation. Agree and configure bounded retention before sustained ingestion;
sharing a bucket must not create an unbounded storage bill.

## Validate and deploy

```bash
helm dependency build infra/helm/openobserve
bash infra/helm/openobserve/test-managed.sh
node --test .github/scripts/openobserve-smoke.test.mjs
```

After the workflows land on main, dispatch **OpenObserve Deployment**, choosing
`staging` for staging alone or `canary` for staging → canary. A canary rollout
always requires that run's staging qualification; there is no direct canary or
production path. PRs and ordinary pushes only validate/package, never deploy.

Validation builds locked chart dependencies, checks all overlays and packages
one chart artifact. Both deployment jobs consume that same artifact, including
its environment overlays. Jobs run trusted main code, use the existing CI-only
environment deployment identity and observability concurrency lane, and refuse
to adopt another release's resources. No deployment kubeconfig is loaded in an
orb. CI checks CNPG, ESO/store readiness and `hcloud-volumes`, then waits for
workloads and metadata readiness and runs a private authenticated three-signal
probe: OTLP metrics → PromQL value/label, JSON logs → SQL value, OTLP traces →
SQL trace identity. Fresh run IDs avoid accepting a previous run's samples.
Local probe tests simulate the API; only the deployed CI run qualifies OpenObserve.

Before installation, CI verifies ready general-pool CPU/memory/pod capacity
against the rendered footprint and pending work, reserving a 1-CPU/1-GiB server
surge slot. This conservative first-install check counts existing OpenObserve
pods too on upgrades; it can reject an upgrade rather than consume headroom.
It then checks the shared bucket has no lifecycle rules, lists only the isolated
prefix, round-trips a run-scoped disposable object there and rejects anonymous
access to that object. Unknown/forbidden lifecycle inspection fails closed.
Only that run's temporary key is removed, including after a failed read check;
cleanup failure blocks installation. Existing Pulse/ESO credentials enter this
disposable pod by Secret reference, never an agent session or CI log.

All backend, NATS and database pods are pinned
away from the processor pool. Services stay private ClusterIP; the probe needs
neither public ingress nor credentials in logs. Failed deployments retain state
without automatic rollback or uninstall; only disposable probe pods and local
CI credentials are removed. Failure diagnostics omit application logs, rendered
manifests, Secret values and event messages.

Before collector fan-out: prove authenticated ingestion, S3 persistence and
query after pod restart, plus metadata failover. Then add independent Alloy write
queues without changing Cloud/Pulse delivery. Use the existing production query
inventory and rerun the exact Kura latency expression after its full window has
accumulated. Compare labels, values, freshness and missing series—not merely 200s.
Metrics can use Grafana's native Prometheus datasource; LogQL/TraceQL consumers
need separate SQL migration or another compatible backend. Shadow notification
tests must not duplicate real pages. Keep Cloud alerts authoritative until proven.

Removing Cloud ingest, changing alert bindings, enabling destructive retention,
and deleting this release/PVCs are separate reviewed operations. Do not uninstall
a stateful evaluation to recover a failed rollout without inspecting its data.
