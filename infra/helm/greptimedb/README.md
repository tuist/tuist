# Pulse on GreptimeDB

Pulse remains the deployed service and product. The existing `pulse` Helm release,
Service `pulse:4000`, ingestion hosts and credentials are the stable contract.
GreptimeDB is the replacement engine underneath that contract, not a separate
customer-facing service. Its source is forked into [`pulse/`](../../../pulse/FORK.md)
and released as `ghcr.io/tuist/pulse` by `pulse-release.yml`. Deployments still
pin the upstream Apache-2.0 GreptimeDB v1.3.0 image; switching them to a fork
image is one change across every pin listed in `pulse/FORK.md`.

Qualify the private backend separately before replacing the existing Pulse
ingestion runtime. Backend qualification and origin replacement both support
staging, canary and production. A dispatch without `replace_pulse` installs the
private backend and never switches ingestion; the cutover is a separate dispatch,
and canary/production dispatches still need their protected-environment approval.
Pushes and pull requests only validate; they never
deploy this replacement. Existing private `greptimedb` resources and their PVC
retain their names and ownership so a branding change cannot recreate storage.

## Bootstrap prerequisites

These are desired configuration, **not a record of provisioned resources**:

- Preserve `tuist-pulso-{staging,canary,production}` and their bucket-scoped
  credentials. The historical bucket names are intentional; Greptime writes under
  its own `greptimedb/` prefix and never rewrites legacy Pulse objects.
- In each environment's `onepassword` ClusterSecretStore vault, provide
  `PULSE_TOKEN/password`, `PULSE_SECRET_KEY_BASE/password` and
  `PULSE_S3_CREDENTIALS` fields `access_key_id` and `secret_access_key`. Keep the
  existing values: collectors and external hosts authenticate with the same token.
- External NixOS cache hosts need opnix access to the **matching environment's**
  `PULSE_TOKEN/password`. Never substitute a production token on staging/canary.
- Confirm the ESO store is ready, the CI environment has its usual
  `OP_SERVICE_ACCOUNT_TOKEN`, and the general pool has the requested capacity.

## Topologies

`topology: standalone` (staging and canary) is not HA: S3 contains flushed
data/indexes; the retained 10 GiB `hcloud-volumes` PVC holds raft-engine WAL and
standalone state. Restart qualification does not prove diskless restore or
disaster recovery.

`topology: cluster` is the only topology the chart renders for production
(`values-production.yaml`). Every component runs one replica per general node
with a `maxUnavailable: 1` disruption budget:

| Component | Replicas | Role |
| --- | --- | --- |
| `greptimedb-etcd` | 3 | Dedicated metadata quorum, never the Kubernetes etcd |
| `greptimedb-kafka` | 3 | KRaft brokers/controllers holding the remote WAL |
| `greptimedb-metasrv` | 3 | Leader-elected through etcd; region failover enabled |
| `greptimedb-datanode` | 3 | Regions; local disk is a rebuildable cache |
| `greptimedb-frontend` | 2 | Authenticated HTTP API behind Service `greptimedb:4000` |

WAL topics use replication factor 3, `min.insync.replicas=2`, no unclean leader
election and no time-based retention; Greptime prunes them after flushing to
object storage. Greptime v1.3.0 produces WAL records with `acks=all` (its pinned
rskafka client sends `acks=-1`), so an acknowledged write is on at least two
brokers. Local-WAL failover (`allow_region_failover_on_local_wal`) stays off and
missing WAL entries are an error (`overwrite_entry_start_id = false`). Cluster
data lives under `greptimedb/distributed/` so it never mixes with a standalone
backend's objects in the same bucket. The target is surviving one general-node
failure without losing acknowledged writes; every general node is in
`fsn1-dc14`, so this is not datacenter resilience.

Initial requests total 8.6 CPUs and 17 GiB. The install's capacity gate places
every replica on a distinct host, keeps the server's 1-CPU surge slot, and with
the cluster topology must still fit after losing any one general node
(`CAPACITY_TOLERATE_NODE_LOSS=1`). The workflow refuses to switch an existing
environment between topologies in place, because Helm would delete the other
topology's workloads. Moving staging or canary to the cluster topology needs
more capacity there and a separate data migration.

The cluster topology was rehearsed outside Kubernetes with the rendered configs
(only addresses rewritten), the real v1.3.0, etcd 3.6.16 and Kafka 4.3.2
binaries and MinIO for object storage. The rehearsal ran
`greptimedb-smoke.mjs` and read its data back through the other frontend. Under
continuous acknowledged writes across three partitions, it SIGKILLed and then
restarted a datanode (automatic region failover), a Kafka broker, the metasrv
leader, an etcd member, a frontend, and finally all three datanodes at once.
All 9,287 acknowledged writes read back. The longest client-visible write
outage was 15.8 s, and the ISR returned to three brokers. This is not a
Kubernetes rehearsal: scheduling, volumes, probes and network policies are only
exercised by the first real install.

Production standalone sizing (CPU 1 / memory 2 GiB) no longer applies. Capacity
gates include the backend before installation and the replacement gateway
before cutover. The gate counts this release's running pods once (as the
planned replacement), so upgrading an installed cluster is not refused for
needing its own capacity twice. `pulse-readiness.sh` follows the installed
topology: behind the replacement gateway it requires every cluster workload
(etcd, Kafka, metasrv, datanodes, frontends) to be Helm-owned, fully rolled out
and Ready at its minimum replica count, or the single standalone StatefulSet.
Each cluster workload restarts when its own rendered configuration changes, not
on unrelated value changes.

## Deployment order and gates

`Pulse GreptimeDB Replacement` accepts `environment=staging`, `canary` or
`production` for backend qualification; this selects the
protected CI environment, kubeconfig vault, shared observability concurrency
lane and isolated `tuist-pulso-<env>/greptimedb/` bucket/prefix. Namespace is
always `observability`. Never read credentials into agent context.
Canary/production reject only `inspect_readers` before loading credentials.
Every replacement checks serving reader compatibility: it refuses while any
enrolled server reader is not already on the Greptime backend. Atlas no longer
has `/mcp` upstreams on Pulse (`../atlas/values-managed-production.yaml`); the
gateway does not implement that API.
Reader configuration belongs
in declarative deployment configuration, not an independent script that patches
the live server Deployment and is later overwritten by its owner.

1. Dispatch with `dashboard=true`, `replace_pulse=false`,
   `deploy_collectors=false`. Ownership, storage class, capacity, ESO, S3 privacy,
   lifecycle and isolated-prefix gates must pass before the backend install.
   The `PULSE_S3_CREDENTIALS` key must have `s3:GetLifecycleConfiguration` on
   its own bucket (`arn:aws:s3:::tuist-pulso-<env>`); unknown lifecycle access
   fails closed. A denied lifecycle read cannot establish the absence of expiry
   rules. Do not grant lifecycle-write or cross-bucket permissions, broaden IAM or
   bypass the probe. The older staging pilot b553e47 was qualified by CI run
   42847871702 attempt 2; that is not qualification of this replacement.
2. CI applies `ALTER DATABASE public SET 'ttl' = '7d'` in staging/canary,
   **`ALTER DATABASE public SET 'ttl' = 'forever'` in production**, and asserts
   persisted `SHOW CREATE DATABASE public` before ingestion and after restart.
   Production's old configured logs30/traces14/metrics90 retention was observe
   only, so an enforced trial TTL would unexpectedly expire data. Expiry is
   asynchronous, not a disk quota. Table-specific TTL overrides take precedence;
   do not introduce overrides that undermine the selected database policy.
3. CI bootstraps native OTLP metrics/logs/traces and their canonical schemas,
   then installs `loki-otlp.yaml` as privileged pipeline `loki_otlp`. Native OTLP
   logs must create `opentelemetry_logs` first (including its standard fulltext
   and scope columns). Smoke checks dashboard SELECT, rejected dashboard
   mutation, rejected writer SELECT, unauthenticated rejection, then rereads the
   same three signals after a StatefulSet restart without rewriting them.
4. Dispatch with `dashboard=true,replace_pulse=true` only after reviewing that
   qualification. It repeats the backend gates before upgrading **existing
   release `pulse`** using `greptimedb-ingest`, with `--reset-values --atomic`.
   Preflight requires existing Helm ownership, immutable Deployment selectors,
   Service contract and unchanged ESO source/target contents. The gateway smoke
   exercises the old routes with real Prometheus Snappy remote write, Loki JSON
   and Snappy protobuf (including structured metadata), and OTLP traces; it
   queries all three signals directly through dashboard readonly auth.
5. Every origin replacement requires recent real Kubernetes metrics, non-CI
   logs and non-CI traces, even when collectors are left unchanged.
   `deploy_collectors=true` additionally upgrades the existing `k8s-monitoring`
   release through Helm before that check. Prefer `false` when replacing only
   Pulse: existing destinations already use the preserved ingestion origin.
   Idle real workloads fail closed: generate traffic and
   investigate, rather than accepting synthetic smoke as rollout proof. Stable
   `pulse-*` destinations/auth/routes and Grafana Cloud destinations are retained;
   no parallel Greptime fan-out is introduced. Controller metrics token
   forwarding remains unchanged.
6. Staging replacement additionally installs `greptime-grafana-staging` from
   the standalone `greptimedb-grafana` chart after backend/gateway qualification
   and live-data verification.
   No Grafana deployment is requested here for canary/production or Grafana Cloud.
   Validate the live tailnet/browser/data boundary separately; Helm readiness is
   not evidence of those boundaries.
7. Grafana queries the private backend directly; product-reader enrollment is
   not a prerequisite. No managed server endpoint, enrollment or feature flag
   changes automatically. Before step 4, the workflow requires converged server
   Deployments and inspects **every serving replica's runtime configuration**.
   Servers without an enrolled Pulse account may remain unchanged. If any
   replica has an enrolled account, it must already have the reader/Greptime
   adapter and the expected backend, URL and database; otherwise cutover fails
   before any Pulse Helm operation. Unknown enrollment, incomplete rollouts and
   failed or ambiguous inspections also fail closed. Raw RPC output stays private.
   For an enrolled reader, deploy its declarative settings through its existing
   owner and validate its three signal pages before cutover. Server endpoint:
   `http://greptimedb.observability.svc.cluster.local:4000`, database `public`,
   username `dashboard`, existing `TUIST_PULSE_TOKEN` password.
   Canary has no enrolled product reader by default. Production is configured
   for account `3` on legacy Pulse: qualify the private production backend
   first, then change its declarative reader settings through the normal server
   deployment owner and verify all serving replicas before replacing the origin.
   Never land that reader switch before the backend is qualified. Do not remove
   enrollment or disable an enabled account flag to bypass compatibility checks.
   Logs/traces support literal
   text search rather than LogQL/TraceQL, and Errors are unavailable in this mode;
   this is not yet Grafana feature parity or approval to retire Cloud.

### Full staging rehearsal

Backend qualification alone does not qualify a cutover. Set `inspect_readers=true`
on a backend-only staging dispatch to report serving images, the live `tuist`
account ID, configured enrollment and the Pulse flag. This is an optional read-only
inspection **within a backend qualification run**, not a read-only dispatch: the
backend install and restart still run. It does not enable flags or print tokens.
Runtime stdout/stderr are captured privately and removed during CI cleanup;
only numeric account IDs, boolean configuration checks and selected image/revision
metadata reach logs. Endpoint strings and raw RPC errors are withheld.
Inspection works before the adapter is installed and reports reader/adapter
availability explicitly; it does not call application APIs added by the adapter.
Do not assume staging uses the production account ID or enable readers before
confirming the account and flag. Keep managed reader settings unchanged until then.

Before replacing the origin, inspect the existing server enrollment. For a
Grafana-only deployment with no enrolled product readers, leave server settings,
images and feature flags unchanged; do not deploy the umbrella server/fleet
release to enable unused readers. Verify the private Grafana with real data and
its actual tailnet identity boundary. If product readers are enrolled, record
their deployed image/chart, prepare a reader rollback through their existing
owner, and exercise the authenticated metrics, logs and traces pages. Do not
substitute a synthetic local UI for these live acceptance checks.

After cutover with real collectors, record non-CI signal identities and run an
ordinary staging server deployment with the replacement active. Then rehearse
the origin rollback below, restore any changed reader backend through its
existing deployment owner, and query the recorded Greptime identities read-only
to prove data survived rollback. Verify old Pulse ingestion and reader recovery
separately. Only then consider another staging cutover or promotion. None of
these steps authorizes removing Grafana Cloud destinations, rules or dashboards.

## Routine deployments remain independent

The server's collector readiness gate follows the actual live `pulse` Deployment.
A healthy versioned Pulse image passes without querying any Greptime resource.
Only a replacement gateway selects the separate Greptime readiness checks; unhealthy,
foreign-owned, unexpected-image and overlapping legacy writers still fail closed.
The migration executes this same gate before and after replacing the gateway.
The observability concurrency lane serializes migration and routine collector
upgrades. Backend qualification alone leaves Pulse and its query clients unchanged.

The legacy Elixir Pulse release and deployment workflows were removed with its
source. An environment still running legacy Pulse keeps its last Helm release
until its replacement; it can no longer be redeployed from this repository.

## Same ingestion origin, deliberately smaller public API

The independent `greptimedb` release owns the private backend. The existing
`pulse` release becomes a single-container compatibility gateway pinned to
`nginxinc/nginx-unprivileged:1.28.0-alpine`. It preserves Service `pulse:4000`,
Ingress `pulse`, TLS Secret `pulse-tls`, ServiceAccount `pulse`, and existing
`pulse-credentials` ESO ownership and contents. Deployment metadata identifies
`greptimedb-ingest`, but immutable selector and Pod labels stay
`app.kubernetes.io/name=pulse,app.kubernetes.io/instance=pulse`.

Public hosts stay `pulse-staging.tuist.dev`, `pulse-canary.tuist.dev`, and
`pulse.tuist.dev`. Only three Exact ingest routes are exposed:

| Existing route | Backend route |
| --- | --- |
| `/api/v1/write` | `/v1/prometheus/write` |
| `/loki/api/v1/push` | `/v1/loki/api/v1/push` |
| `/v1/traces` | `/v1/otlp/v1/traces` |

Internal aliases `/v1/{metrics,logs,traces}` and `/otlp/v1/*` map to native OTLP.
All ingest requests must be POST with no query string. The gateway fixes the
database to `public`, trace pipeline to `greptime_trace_v1`, trace table to
`opentelemetry_traces`, and Loki pipeline/table to `loki_otlp` /
`opentelemetry_logs`. Client database/table/pipeline/version/params headers cannot
override these targets. Basic auth, payload bytes, encodings and upstream status
are passed unchanged. No retries/replay are performed. The 4 MiB wire-body bound
preserves the old managed Ingress and endpoint limit; the old 16 MiB decompressed
limit was not a 16 MiB wire allowance.

`/mcp`, SQL/admin/query paths and arbitrary routes are **not** forwarded. This
does not preserve legacy Pulse query/MCP APIs. Existing private Grafana readers
using username `tuist` cannot read through the write-only identity; use the
dashboard readonly backend integration instead. The unsigned SQL plugin is not
available in Grafana Cloud; its builtin Prometheus path is the metrics option.

## Authentication, schema and network

Existing `greptimedb-auth` pilot credentials are created once by CI and never
rotated/read back. Pilot is for CI qualification only. With `dashboard.enabled`,
ESO reads existing `PULSE_TOKEN/password` into a separate provider file containing
`dashboard:ro=<token>` and `tuist:wo=<token>`. A nonroot init container combines
projected inputs into memory without exposing Secrets to Helm or agent context.
Static providers load at startup; restart after ESO credential rotation. Tokens
must be single-line and contain no `=` (the static-file delimiter). Static modes
are not per-table/per-tenant authorization; server account authorization remains
necessary.

Logs retain native `timestamp`, `body`, `resource_attributes`, `severity_text`,
`trace_id`; traces expose `timestamp`, `service_name`, `span_name`,
`duration_nano`, `span_status_code`, `trace_id`. Loki normalization keeps labels
and metadata separately in JSON resource/log attributes, preserves nanosecond
timestamps, maps `service_name` to `service.name`, prefers metadata trace IDs and
stream severity. No optional flattened resource keys are required by the adapter.

Backend NetworkPolicy preserves observability inputs and adds distinct TCP 4000
peers for server component pods and exact PDC-agent labels (name=tuist,
instance=tuist, component=pdc-agent). Namespace and Pod selectors are ANDed:
`tuist-staging`, `tuist-canary`, **`tuist` for production**. No backend public
Ingress exists. Parent manages server/PDC endpoint configuration.

## Rollback boundaries

The gateway uses Recreate to avoid overlapping legacy writers; expect a brief
ingest interruption and rely on client retries. `--atomic` rolls back only the
`pulse` Helm release if its Helm rollout fails. A **later smoke/live-data failure
does not automatically roll back**; stop promotion and explicitly choose the
known-good prior Pulse revision. Backend release/PVC/S3 history remain untouched.
New Greptime data are not copied back to old Pulse, and historical Pulse objects
are neither imported nor deleted. Do not uninstall the backend or shrink its PVC
as a rollback shortcut.

The cutover records the deployed Pulse chart/revision in its run summary.
Dispatch `Pulse GreptimeDB Replacement` on trusted main with the selected
`environment` and `rollback_pulse_revision=<recorded revision>`. This selects
the separate rollback job, not the backend deployment or collector rollout.
The selected environment controls the protected CI environment, kubeconfig vault
and observability concurrency lane for rollback too. It refuses unknown
environments, nonnumeric/unknown revisions, revisions
that are not a deployed/superseded `pulse-*` chart, and deployments that are not
the Helm-owned replacement gateway. It rolls back only release `pulse`, waits
for readiness, and executes the same legacy-writer/readiness gate as routine
deploys. It never upgrades/uninstalls Greptime or touches its PVC/S3 objects.

This restores the ingestion origin only. Explicitly restore the reader backend
using the previously recorded chart/image and that environment's normal server deployment;
until then readers continue querying Greptime and will not see new Pulse writes.
Backend data preservation and both reader/ingest recovery must be demonstrated
with live reads; a successful Helm rollback is not that evidence.

## Uninstalling the old pulse release

No collector writes to Pulse any more, so the old `pulse` release (gateway in
staging, Elixir Pulse in canary and production) is removed by dispatching with
`environment` and `uninstall_pulse=true`. That runs only the `uninstall-pulse`
job: no backend install and no collector rollout. It refuses while the
environment's `k8s-monitoring` values, live `k8s-monitoring-*` ConfigMaps, or
any pod outside the release still reference `pulse.observability` or
`pulse-credentials`, because Alloy drops its whole config, Grafana Cloud
included, when a referenced Secret is missing. Deploy the server to that
environment first. It then runs `helm uninstall pulse --keep-history`, which
removes `pulse-credentials` with the release and never touches Greptime, its
PVCs or bucket objects, and finishes with the routine readiness gate.

The backend deploy's storage probe does not depend on either release's
Secret: it creates a run-scoped ExternalSecret from the rendered chart's
`PULSE_S3_CREDENTIALS` references and deletes it afterwards, so it works before
the first install and after the old release is gone.

## Validation

```bash
bash infra/helm/greptimedb/test-managed.sh
bash infra/helm/greptimedb-ingest/test-managed.sh
NGINX_BINARY=/usr/sbin/nginx node --test .github/scripts/greptimedb-gateway.test.mjs
node --test .github/scripts/greptimedb-replacement-preflight.test.mjs
node --test .github/scripts/greptimedb-storage.test.mjs
node --test .github/scripts/pulse-readiness.test.mjs
helm repo add grafana https://grafana.github.io/helm-charts
helm dependency build infra/helm/k8s-monitoring
bash .github/scripts/greptimedb-collectors.test.sh
```

CI also lint/renders the staging Grafana chart and runs its Python tests in an
isolated venv with PyYAML; no dependency is added to Pulse runtime. Local binary
protocol tests do not prove S3 behavior, capacity, live ingress/NetworkPolicy,
browser/tailnet access, or any staging/canary/production rollout.

Versioned references: [static permission modes](https://docs.greptime.com/1.3/user-guide/deployments-administration/authentication/static),
[ALTER DATABASE TTL](https://docs.greptime.com/1.3/reference/sql/alter),
[SHOW CREATE DATABASE](https://docs.greptime.com/1.3/reference/sql/show).
