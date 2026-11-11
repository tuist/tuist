# GreptimeDB replacement

Private Apache-2.0 GreptimeDB v1.3.0 standalone backend, qualified separately
before replacing the existing Pulse ingestion runtime. The replacement workflow
is **staging-only**. Canary and production continue using Pulse; promotion needs
a separate reviewed change after staging evidence. Pushes and pull requests only
validate; they never deploy this replacement.

This is not HA: S3 contains flushed data/indexes; the retained 10 GiB
`hcloud-volumes` PVC holds raft-engine WAL and standalone state. Restart
qualification does not prove diskless restore or disaster recovery. Production
requests CPU 1 / memory 2 GiB with a 4 GiB memory limit, preserving the old
Pulse resource envelope; staging/canary retain trial sizing. Capacity gates
include the backend before installation and replacement gateway before cutover.

## Deployment order and gates

`GreptimeDB Staging Replacement` accepts only `environment=staging`; this selects the
protected CI environment, kubeconfig vault, shared observability concurrency
lane and isolated `tuist-pulso-<env>/greptimedb/` bucket/prefix. Namespace is
always `observability`. Never read credentials into agent context.

1. Dispatch with `dashboard=true`, `replace_pulse=false`,
   `deploy_collectors=false`. Ownership, storage class, capacity, ESO, S3 privacy,
   lifecycle and isolated-prefix gates must pass before the backend install.
   Canary may still need the narrowly scoped `s3:GetLifecycleConfiguration`
   permission; unknown lifecycle access fails closed. Do not broaden IAM or
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
5. `deploy_collectors=true` additionally upgrades the existing `k8s-monitoring`
   release through Helm, then requires recent real Kubernetes metrics, non-CI
   logs and non-CI traces. Idle real workloads fail closed: generate traffic and
   investigate, rather than accepting synthetic smoke as rollout proof. Stable
   `pulse-*` destinations/auth/routes and Grafana Cloud destinations are retained;
   no parallel Greptime fan-out is introduced. Controller metrics token
   forwarding remains unchanged.
6. Staging replacement additionally installs `greptime-grafana-staging` from
   the standalone `greptimedb-grafana` chart after backend/gateway qualification
   (and after live-data verification when collector rollout was selected).
   No Grafana deployment is requested here for canary/production or Grafana Cloud.
   Validate the live tailnet/browser/data boundary separately; Helm readiness is
   not evidence of those boundaries.
7. The server adapter is restored but defaults to Pulse. No managed server
   endpoint or enrollment changes automatically. **Before step 4**, deploy the
   adapter image to staging, then explicitly enable `TUIST_PULSE_BACKEND=greptime`
   for the enrolled staging account and validate its three signal pages.
   The replacement refuses cutover until staging server Deployments have converged
   with that backend, URL and database. Server endpoint:
   `http://greptimedb.observability.svc.cluster.local:4000`, database `public`,
   username `dashboard`, existing `TUIST_PULSE_TOKEN` password.
   Keep canary/production server values unchanged. Logs/traces support literal
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

Before replacing the origin, record the currently deployed server image and
chart commit and prepare a reader rollback using the normal staging server
deployment workflow. Deploy the adapter and verified account settings to staging
only, then exercise the authenticated metrics, logs and traces pages. Do not
substitute a synthetic local UI for these live acceptance checks.

After cutover with real collectors, record non-CI signal identities and run an
ordinary staging server deployment with the replacement active. Then rehearse
the origin rollback below, restore the prior reader backend through a normal
staging server deployment, and query the recorded Greptime identities read-only
to prove data survived rollback. Verify old Pulse ingestion and reader recovery
separately. Only then consider another staging cutover or promotion. None of
these steps authorizes removing Grafana Cloud destinations, rules or dashboards.

## Routine deployments remain independent

The server's collector readiness gate follows the actual live `pulse` Deployment.
A healthy versioned Pulse image passes without querying any Greptime resource.
Only a staging gateway selects the separate Greptime readiness checks; unhealthy,
foreign-owned, unexpected-image and overlapping legacy writers still fail closed.
The migration executes this same gate before and after replacing the gateway.
The observability concurrency lane serializes migration and routine collector
upgrades. Backend qualification alone leaves Pulse and its query clients unchanged.

Pulse publication/deployment workflows remain available for environments still
using Pulse. Their instance preflight refuses to overwrite an existing Greptime
gateway even though it retains the same Helm release owner. An attempted automatic
Pulse promotion stops there rather than silently restoring the old writer.

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
as a rollback shortcut. The independent Pulse deployment preflight intentionally
refuses this gateway; do not rerun a Pulse release to force recovery.

The cutover records the deployed Pulse chart/revision in its run summary.
Dispatch `GreptimeDB Staging Replacement` on trusted main with
`environment=staging,rollback_pulse_revision=<recorded revision>`. This selects
the separate rollback job, not the backend deployment or collector rollout.
It refuses non-staging environments, nonnumeric/unknown revisions, revisions
that are not a deployed/superseded `pulse-*` chart, and deployments that are not
the Helm-owned replacement gateway. It rolls back only release `pulse`, waits
for readiness, and executes the same legacy-writer/readiness gate as routine
deploys. It never upgrades/uninstalls Greptime or touches its PVC/S3 objects.

This restores the ingestion origin only. Explicitly restore the reader backend
using the previously recorded chart/image and normal staging server deployment;
until then readers continue querying Greptime and will not see new Pulse writes.
Backend data preservation and both reader/ingest recovery must be demonstrated
with live reads; a successful Helm rollback is not that evidence.

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
