# GreptimeDB staging pilot

Private, synthetic-only evaluation of the Apache-2.0 GreptimeDB v1.3.0 core.
This is not a fork, a Pulse replacement, a Grafana cutover, or a production rollout.
One standalone instance avoids introducing Kafka, etcd or ClickHouse for the trial.
It is not HA: S3 stores flushed data and indexes, while the retained 10 GiB
`hcloud-volumes` PVC contains local raft-engine WAL and local standalone state.
Neither a successful restart nor sharing a bucket establishes diskless durability.

## Deployment and prerequisites

`GreptimeDB Staging Pilot` validates/packages on PRs and main pushes. Deployment
is manual-only, trusted main, using the existing staging CI identity and shared
observability deployment concurrency lane. No CI kubeconfig or Kubernetes Secret
is read into an agent session. There is deliberately no canary/production job yet.

Before installation, the workflow checks resource ownership, general-pool capacity
with a reserved server surge slot, ESO readiness, the storage class and the shared
bucket. It reuses the existing storage/capacity probes. The storage probe must
verify no lifecycle rules, private object access and a round trip under
`s3://tuist-pulso-staging/greptimedb/ci-preflight/`. It deletes only its own probe.
Unknown/forbidden lifecycle inspection blocks installation; do not bypass it.
The previous OpenObserve prerequisite run returned 403 AccessDenied for lifecycle
inspection. The staging bucket credential needs `s3:GetLifecycleConfiguration`
before this path can qualify; changing provider permissions is a separate human step.

ESO reads the staging vault's existing `PULSE_S3_CREDENTIALS` fields into a separate
Secret with GreptimeDB's expected environment keys. S3 data uses `greptimedb/`,
never Pulse's `tenants/` or `system/`, or OpenObserve's `openobserve/`.
A prefix isolates object names, not IAM or bucket-wide lifecycle rules. Existing
Pulse objects cannot be queried just by pointing GreptimeDB at the same bucket.

CI creates the independent `greptimedb-auth` file once, never reads it back and
never rotates it on reruns. Only the backend and disposable probe mount it.
The pilot user is an evaluation identity, not a tenant-isolation or read-only
authorization boundary. Create scoped ingestion/query identities before sustained
traffic or granting dashboard access; keep credentials out of browser code.
Services have no public ingress and accept HTTP only from `observability` pods.

After installation CI writes fresh OTLP protobuf metrics, an ERROR log and an
error-status span, checks PromQL value/label and SQL identities, rejects anonymous
SQL, restarts the StatefulSet and reads the same samples without writing them
again. State/PVCs are retained on failure; only disposable probes are cleaned up.
This proves a pod restart using its existing PVC, not S3-only restore or HA.
Object-store flush/restore and backup testing remain gates before real ingestion.

## Headless integration boundaries

- **Grafana metrics:** native Prometheus datasource at
  `http://greptimedb.observability:4000/v1/prometheus`, Basic Auth, and
  `x-greptime-db-name: public`, reached through a separately verified private
  datasource connection. Add a non-default shadow datasource; do not retarget
  existing panels or alerts. ClusterIP alone is not reachable from Grafana Cloud.
- **Grafana logs/traces:** SQL/MySQL or the GreptimeDB plugin, not a Loki/Tempo URL
  swap. Upstream's current plugin is unsigned and outside the catalog, so do not
  assume it can be installed in our managed Grafana Cloud stack.
- **Pulse product dashboard:** `server/lib/tuist/pulse.ex` currently uses Prometheus,
  LogQL, Tempo/TraceQL and Pulse-native error endpoints with bearer/tenant auth.
  Changing `TUIST_PULSE_URL` would break that contract. Introduce and qualify
  signal-specific server-side integration before pointing this UI at GreptimeDB;
  preserve account authorization, filters, pagination and error detail sanitization.
- **Error tracking:** storing ERROR logs/error spans does not provide Sentry issue
  grouping, fingerprints, releases, symbolication or the Pulse errors API.
- **License:** the pinned core's Apache-2.0 license permits commercial modification
  and embedding, subject to its license/notice obligations. Enterprise features,
  dependencies and trademarks require their own review. No fork is needed to use APIs.

No collector fan-out, customer telemetry, destructive retention, dashboard bindings,
alert notifications or defaults change in this pilot. Synthetic samples are small
and retained until explicit cleanup; sustained ingestion requires bounded retention
and the data-export inventory to be extended before collection. Keep Grafana Cloud
authoritative until the actual dashboard/alert inventory passes value/label/freshness
comparisons, including known GreptimeDB PromQL and trace-API gaps.

## Local validation

```bash
bash infra/helm/greptimedb/test-managed.sh
node --test .github/scripts/openobserve-preflight.test.mjs
node --check .github/scripts/greptimedb-smoke.mjs
```

The smoke script runs in CI with a mounted auth file. Local validation of that
script against filesystem-backed v1.3.0 is useful protocol evidence, not evidence
of Tigris compatibility or a successful staging deployment.
