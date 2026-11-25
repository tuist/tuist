# Pulse

Pulse is Tuist's observability database: its source is in [`pulse/`](../../../pulse/FORK.md)
and its release workflows publish it as `ghcr.io/tuist/pulse`: a canary for
every `pulse/` change on main, then release candidates and weekly stable
releases (see `FORK.md`). In each workload cluster this chart runs it as the
private `pulse` release in namespace
`observability`, behind Service `pulse` (`pulse.observability.svc.cluster.local:4000`).
Every resource is named `pulse` or `pulse-*`, the default catalog is `pulse`,
configuration variables use the `PULSE_STANDALONE__` and `PULSE_DATANODE__`
prefixes, and clients select a database with `X-Pulse-DB-Name`. Kafka WAL
topics are `pulse_wal_topic_*`. Each region keeps the topic it was created
with, so regions created before the rename keep their earlier topics until their
tables are recreated.

Every environment runs a renamed release. Releases before the rename
(`1.3.0-1`) wrote into a catalog of their own, which stays in metadata and in
the bucket but is no longer queried. A renamed release reads only `X-Pulse-*`
headers, so the deployment refuses to run while live collectors that write to
Pulse lack them: deploy the server to that environment first.

Pulse deploys continuously, like Kura. Every push to main that changes
`pulse/`, this chart or its deployment runs `Pulse Production Deployment`: it
publishes a canary when `pulse/` changed, then deploys staging, canary and
production in turn, each only after the previous environment qualified. Each
leg runs the newest `pulse@*-canary.*` the commit contains; `values.yaml` pins
the image used only for a commit without one. Pull requests only validate. A
`Pulse Deployment` dispatch from main redeploys or rolls back one
environment.

## Bootstrap prerequisites

These are desired configuration, **not a record of provisioned resources**:

- Preserve `tuist-pulso-{staging,canary,production}` and their bucket-scoped
  credentials. The historical bucket names are intentional; Pulse writes under
  its own `pulse/` prefix.
- In each environment's `onepassword` ClusterSecretStore vault, provide
  `PULSE_TOKEN/password` and `PULSE_S3_CREDENTIALS` fields `access_key_id` and
  `secret_access_key`. Keep the existing values: collectors authenticate with
  the same token.
- Confirm the ESO store is ready, the CI environment has its usual
  `OP_SERVICE_ACCOUNT_TOKEN`, and the general pool has the requested capacity.
- The management cluster runs its own standalone Pulse, installed by Flux
  (`infra/flux/pulse`) with `values-management.yaml`, so its metrics never
  depend on a workload cluster. Management's collectors write their metrics
  only to it. It writes `tuist-pulso-production/management/`
  with the **`tuist-k8s-mgmt`** vault's `PULSE_TOKEN` and
  `PULSE_S3_CREDENTIALS`, a Tigris key whose IAM policy allows only that prefix,
  so management can never read or delete production's `pulse/`
  (`mgmt-cluster-apply.yml` creates its `pulse-auth` Secret), and
  keeps its WAL and catalog on `tuist-mgmt`'s `/var/lib/tuist-pulse` because
  management has no volume provisioner. CI's TTL and storage checks do not run
  there; it keeps data indefinitely. Grafana reaches it through its own PDC
  agent (`infra/flux/pulse-pdc`), whose token is `PDC_AGENT/password` in the
  same vault.

## Topologies

`topology: cluster` is the only topology the chart renders for workload
clusters (staging, canary and production). Every component runs one replica per
general node with a `maxUnavailable: 1` disruption budget:

| Component | Replicas | Role |
| --- | --- | --- |
| `pulse-etcd` | 3 | Dedicated metadata quorum, never the Kubernetes etcd |
| `pulse-kafka` | 3 | KRaft brokers/controllers holding the remote WAL |
| `pulse-metasrv` | 3 | Leader-elected through etcd; region failover enabled |
| `pulse-datanode` | 3 | Regions; local disk is a rebuildable cache |
| `pulse-flownode` | 1 | Runs the [Symptoms](#symptoms-inputs) Flows; keeps no data |
| `pulse-frontend` | 2 | Authenticated HTTP API behind Service `pulse:4000` |
| `pulse-flownode` | 1 | Runs flows (the `error_issues` rollup, see [Errors](#errors)) |

The flownode queries the frontends on their internal gRPC port 4010, which
skips the static users; `pulse-internal` admits only Pulse's own pods to it,
and no policy opens it to clients. Writes and reads never pass through the
flownode, so it has no disruption budget and `pulse-readiness.sh` does not
gate collectors on it; a down flownode only delays the rollup, which the next
deploy's flush recomputes.

The metasrv leader creates the WAL topics once, when it starts leading, and
does not retry, so each metasrv pod first waits until the topics exist or all
three brokers are registered. Otherwise a fresh install can create them before
replication factor 3 is possible and fail every region creation.

WAL topics use replication factor 3, `min.insync.replicas=2`, no unclean leader
election and no time-based retention; Pulse prunes them after flushing to
object storage. Pulse produces WAL records with `acks=all` (its pinned
rskafka client sends `acks=-1`), so an acknowledged write is on at least two
brokers. Local-WAL failover (`allow_region_failover_on_local_wal`) stays off and
missing WAL entries are an error (`overwrite_entry_start_id = false`). Cluster
data lives under `pulse/distributed/` so it never mixes with a standalone
backend's objects in the same bucket. The target is surviving one general-node
failure without losing acknowledged writes; every general node is in
`fsn1-dc14`, so this is not datacenter resilience.

Production's requests (`values-production.yaml`) total 11.65 CPUs and 23.1 GiB.
The chart's defaults size staging and canary, whose whole standalone backend
used about 600 MiB and 0.05 CPU, at 2.05 CPUs and 5.9 GiB. The install's capacity
gate places every replica on a distinct host, keeps the server's 1-CPU surge
slot, and must still fit after losing any one general node
(`CAPACITY_TOLERATE_NODE_LOSS=1`).

`topology: standalone` remains only for management, which has no volume
provisioner: one StatefulSet with a raft-engine WAL on local disk. It is not HA.

### Moving staging or canary off standalone

Staging and canary first ran the standalone topology. A deployment that finds
its `statefulset/pulse` moves it to the cluster without dropping reads or
writes, in one run:

1. It installs the cluster beside the standalone pod
   (`migration.standalone=serving`). Service `pulse` stays on that pod, which
   the chart renders unchanged so it does not restart; the run fails if its
   UID or restart count changes. Its own NetworkPolicy and
   CiliumNetworkPolicy select it as the only Pulse pod without
   `app.kubernetes.io/component`: Cilium leaves
   `statefulset.kubernetes.io/pod-name` out of pod identities, so a policy on
   that label never matches. The side-by-side phase only has to fit now; the
   cluster alone must still fit after losing a node.
2. It smoke-tests the frontends through Service `pulse-frontend`.
3. It moves Service `pulse` to the frontends (`migration.standalone=draining`)
   and runs the usual smoke, restart and telemetry checks against it. If they
   fail, it rolls back one revision, which moves readers back to the
   standalone pod.
4. It removes the standalone StatefulSet. Its `data-pulse-0` claim is
   retained; delete it once nothing needs a rollback.

The cluster starts empty: it writes under `pulse/distributed/` and does not
read the standalone backend's `pulse/` data, so dashboards lose earlier
history in that environment.

The cluster topology was rehearsed outside Kubernetes with the rendered configs
(only addresses rewritten), the real v1.3.0, etcd 3.6.16 and Kafka 4.3.2
binaries and MinIO for object storage. The rehearsal ran
`pulse-smoke.mjs` and read its data back through the other frontend. Under
continuous acknowledged writes across three partitions, it SIGKILLed and then
restarted a datanode (automatic region failover), a Kafka broker, the metasrv
leader, an etcd member, a frontend, and finally all three datanodes at once.
All 9,287 acknowledged writes read back. The longest client-visible write
outage was 15.8 s, and the ISR returned to three brokers. This is not a
Kubernetes rehearsal: scheduling, volumes, probes and network policies are only
exercised by the first real install.

The capacity gate runs before installation and counts this release's running pods
once (as the planned replacement), so upgrading an installed cluster is not
refused for needing its own capacity twice. `pulse-readiness.sh` follows the
installed topology: it requires every cluster workload (etcd, Kafka, metasrv,
datanodes, frontends) to be Helm-owned, fully rolled out and Ready at its
minimum replica count, or the single standalone StatefulSet where a
migration has not run yet.
Each cluster workload restarts when its own rendered configuration changes, not
on unrelated value changes.

### Datanode restarts

A datanode that stops takes its regions offline until metasrv fails them over,
so reads (Grafana alert rules, dashboards) fail in the meantime. In the
environments listed in `cluster.datanode.drainedRolloutEnvironments` (staging,
canary and production), the chart holds the datanode StatefulSet at
`partition: replicas`, so no template change restarts a datanode by itself.
The deployment then runs
[`pulse-datanode-rollout.sh`](../../../.github/scripts/pulse-datanode-rollout.sh),
which for one datanode at a time moves its leader regions to the others with
`ADMIN migrate_region`, lowers the partition to it, waits for it to be Ready on
the new revision, and moves the same regions back. It ends holding the
partition again. It is upstream's drain-before-restart done from outside
Pulse, so the fork carries no code for it.

- `kubectl rollout restart` alone restarts nothing there; run the script after
  it, as the deployment's reread check does.
- A failed run leaves the partition lowered and some datanodes on the old
  revision, which `pulse-readiness.sh` rejects. Rerun the deployment: the
  script skips datanodes already on the update revision. Regions it moved away
  before failing stay where they are.
- Region failover still covers unplanned stops (node failure, eviction), but
  it never moves regions back, so placement drifts toward the datanodes that
  stayed up. Before restarting anything, every deployment runs the script with
  `rebalance`. That spreads leader regions by stored bytes and moves regions
  only while the fullest and emptiest datanode differ by more than a quarter
  of the mean. To rebalance without a code change, dispatch `Pulse Deployment`
  for that environment.

## Deployment order and gates

`Pulse Deployment` accepts `environment=staging`, `canary` or
`production`; this selects the protected CI environment, kubeconfig vault, shared
observability concurrency lane and isolated `tuist-pulso-<env>/pulse/`
bucket/prefix. Namespace is always `observability`. Never read credentials into
agent context. Canary/production reject `inspect_readers` before loading
credentials. None of these steps changes Grafana Cloud.

Each environment moves in this order:

1. **Install or qualify the backend.** Dispatch with `dashboard=true`. Ownership,
   storage class, capacity, ESO, S3 privacy, lifecycle and isolated-prefix gates
   must pass before the install. The `PULSE_S3_CREDENTIALS` key must have
   `s3:GetLifecycleConfiguration` on its own bucket
   (`arn:aws:s3:::tuist-pulso-<env>`); unknown lifecycle access fails closed. Do
   not grant lifecycle-write or cross-bucket permissions, broaden IAM or bypass
   the probe. CI then applies `ALTER DATABASE public SET 'ttl' = '7d'` in
   staging/canary and **`'forever'` in production**, bootstraps native OTLP
   metrics/logs/traces, the `loki_otlp` pipeline (`loki-otlp.yaml`), the `errors`
   table (`errors.sql`, append-only, 90-day TTL in production, 7 days
   elsewhere), the `error_issue_hours` table and `error_issues` flow
   (`error-issues.sql`), the `sentry_errors` pipeline (`sentry-errors.yaml`;
   see [Errors](#errors)) and the `sessions` table (`sessions.sql`, same TTL as
   `errors`; see [Release health](#release-health)) and,
   once a trace exists, the Symptoms columns, Flows and tables (`symptoms.sql`;
   see [Symptoms inputs](#symptoms-inputs)), flushes the flow, and smoke
   tests dashboard reads, rejected dashboard mutation, rejected writer reads and
   unauthenticated rejection, then rereads the data after restarting every
   stateful component.
2. **Write to Pulse.** Deploy `k8s-monitoring` with its Pulse destinations.
   Server deploys refuse this until `pulse-dashboard-auth` is Ready with its
   ingest keys, because Alloy drops its whole config, every other writer
   included, when a referenced Secret is missing. Then dispatch with
   `dashboard=true,verify_telemetry=true`, which requires recent real Kubernetes
   metrics, non-CI logs and non-CI traces. Idle workloads fail closed: generate
   traffic rather than accepting the synthetic smoke.

Staging dispatches with `dashboard=true` also install `pulse-grafana-staging`
from the `pulse-grafana` chart. Validate its tailnet/browser/data boundary
separately; Helm readiness is not evidence of it.

`inspect_readers=true` (staging only) also reports serving images, the live
`tuist` account ID, configured reader enrollment and the Pulse flag. It prints
only numeric IDs and booleans; raw RPC output is withheld.

Product readers are configured declaratively in the `tuist` chart: staging and
production read Pulse (database `public`,
username `dashboard`); canary has no enrolled reader. Logs and traces support
literal text search rather than LogQL/TraceQL.

## Routine deployments remain independent

The server's collector readiness gate (`pulse-readiness.sh`) follows the live
workloads. With no `pulse` release installed it fails: every environment's
collectors write only to Pulse, so their values reference the
`pulse-dashboard-auth` ingest login, which only the `pulse` chart creates.
Otherwise every workload of the installed topology must
be Helm-owned by `pulse`, fully rolled out and Ready, and run a published
`ghcr.io/tuist/pulse:<version>-<n>` image. The observability concurrency lane serializes these dispatches and
routine collector upgrades.

## Authentication, schema and network

Existing `pulse-auth` pilot credentials are created once by CI and never
rotated/read back. Pilot is for CI qualification only. With `dashboard.enabled`,
ESO reads existing `PULSE_TOKEN/password` into a separate provider file containing
`dashboard:ro=<token>` and `tuist:wo=<token>`. In the environments listed in
`sentryWriter.environments` (none by default) it also holds `sentry:wo=<writer>`
from `PULSE_SENTRY_WRITER/password`, the identity in Sentry producers' DSNs, so a
DSN never carries the dashboard's token. In the environments listed in
`symptomsReader.environments` (none by default) it also holds
`symptoms:ro=<reader>` from `PULSE_SYMPTOMS_READER/password`, the Symptoms
evaluator's own read-only identity, so the evaluator never holds
`PULSE_TOKEN`, which is also the collectors' write password. Pulse's
permission checker lets a `wo` user run every non-read statement, DDL
(`DROP`, `ALTER`, `TRUNCATE`) included, not only inserts. List an environment only once that item
exists in its vault, or the ExternalSecret fails and the deploy stops. Use only
letters and digits for it (1Password's generator adds symbols by default): it
goes into DSNs unescaped, and a `,`, `@`, `/`, `#` or `=` breaks every copy. The
same Secret
(`pulse-dashboard-auth`) carries `ingest-username`/`ingest-password` for the
collectors' write-only identity. A nonroot init container combines
projected inputs into memory without exposing Secrets to Helm or agent context.
Static providers load at startup; restart after ESO credential rotation. Tokens
must be single-line and contain no `=` (the static-file delimiter). Static modes
are not per-table/per-tenant authorization; server account authorization remains
necessary.

Logs retain native `timestamp`, `body`, `resource_attributes`, `severity_text`,
`trace_id`, and Loki lines add the [Symptoms](#symptoms-inputs) columns
`service`, `level`, `template_key`, `template` and `exception_fp`; traces expose `timestamp`, `service_name`, `span_name`,
`duration_nano`, `span_status_code`, `trace_id`. Loki normalization keeps labels
and metadata separately in JSON resource/log attributes, preserves nanosecond
timestamps, maps `service_name` to `service.name`, prefers metadata trace IDs and
stream severity. No optional flattened resource keys are required by the adapter.

Backend NetworkPolicy preserves observability inputs and adds distinct TCP 4000
peers for server component pods and exact PDC-agent labels (name=tuist,
instance=tuist, component=pdc-agent). Namespace and Pod selectors are ANDed:
`tuist-staging`, `tuist-canary`, **`tuist` for production**. No backend public
Ingress exists. Parent manages server/PDC endpoint configuration.
With `dashboard.enabled`, `pulse-private` also admits the symptoms evaluator
(`app.kubernetes.io/name=symptoms`, `component=evaluator`, from
`infra/helm/symptoms`) in `symptoms-<environment>` to TCP 4000; it reads as the
read-only dashboard user.

Environments listed in `pulse.postgres` (`templates/_helpers.tpl`: production)
also serve PostgreSQL on TCP 4003 from the frontends for Grafana's SQL log alerts
(`infra/helm/k8s-monitoring/pulse-grafana.md`), with the same static users. The
NetworkPolicy admits only the PDC agent to that port, and the environment's
`pdcAgent.permitRemoteOpen` must list it. The list lives in the helper, not in
values, so adding an environment restarts only that environment's Pulse.

`pulse-datanode-metrics` admits only k8s-monitoring's `alloy-metrics` pods to
the datanodes' TCP 4000, for the `pulse-datanode` scrape of scan memory and
flush metrics behind the Pulse alerts in
[`alerts.md`](../k8s-monitoring/alerts.md#pulse-rejecting-scans-for-lack-of-memory).

The `pulse-host-ingress` CiliumNetworkPolicy also admits Cilium's `host` and
`remote-node` identities to TCP 4000 on the API pods (the frontends in the
cluster topology). k8s-monitoring's control-plane collector scrapes the local
kube-apiserver and etcd on the host network, so its writes carry a node
identity that Kubernetes `podSelector`/`ipBlock` rules never match; without
this policy Hubble shows them as `POLICY_DENIED` and Pulse has no
`tuist-kube-apiserver` or `tuist-etcd` series. Pulse still authenticates them.

## Errors

Errors are Sentry events stored one row per event in `errors`. Pulse accepts
Sentry envelopes itself (see `pulse/FORK.md`): an SDK whose DSN is
`http://tuist:<password>@pulse.observability:4000/v1/sentry/<service>/1` posts
to `/v1/sentry/<service>/api/1/envelope/`, authenticating as the write-only
`tuist` identity, and Pulse runs each `event` item through the `sentry_errors`
pipeline into `errors`, tagged with `<service>`. Atlas stays every SDK's
DSN. To compare the two, the tuist chart's `sentryPulse` values send a copy of
each error to Pulse from the server's web instances and Kura, per service and
environment and off by default, as the write-only `sentry` user (see
[Authentication](#authentication-schema-and-network)). The
`pulse-private` NetworkPolicy admits only those two producers on port 4000 (Kura
from its `kura` namespace), and `pulse-host-ingress` admits hostNetwork Kura
pods. The
pipeline computes Atlas's fingerprint from the raw event, so an issue is
`(service, fingerprint)` with the fingerprint Atlas has for the same event, and
stores only a scrubbed projection (no user, request headers, cookies, bodies or
query strings, frame variables or module lists; credential, contact and
IP-address keys filtered; credentials in URLs, query strings, emails, bearer and
Basic credentials, Tuist tokens, JWTs and IPv4 and IPv6 addresses redacted in
stored text).

`errors` is append-only (`append_mode`): with `(service, fingerprint)` as the
primary key and no append mode, two different events of one issue at the same
timestamp collapsed into one row (checked against the pinned image). Tables
created before were switched by the deploy's `ALTER TABLE errors SET
'append_mode' = 'true'`, which Pulse allows only in that direction. An SDK's
resend of an event is now a second row with the same `event_id`, so readers
count `DISTINCT event_id` and list events with `SELECT DISTINCT`, as the
server's `Tuist.Pulse.Errors` does.

### Grouping

The fingerprint hashes the first exception's type, its top in-app frame (or
last frame) and the normalized message (or exception value), then `Type: value`
for every further exception in the chain, joined with `|`. Sentry sends a chain
oldest first, so the first exception is the root cause and the rest wrapped it:
the same root cause raised through different callers is a different issue, as
in Sentry. Titles and culprits still come from the first exception and keep the
real text. Events with no exception, frame or message group by logger,
normalized transaction, level and tracing event name, and an SDK `fingerprint`
replaces all of this (`{{ default }}` expands to it).

Normalization replaces values with typed placeholders, in this order, so a URL
or UUID is replaced whole before its digits, and dates, addresses and hex
before ints: `<url>`, `<email>`, `<uuid>`, `<date>` (ISO dates with an
optional time and zone), `<ip>` (IPv4), `<git_sha>` (40 lowercase hex digits),
`<hex>` (`0x…`, or 16 or more hex digits), `<float>`, `<int>`. Whitespace then
collapses and the text is cut at 200 characters. It applies to grouping only.

Changing these rules regroups events. In Pulse an issue only exists within the
query window, so new fingerprints simply start new issues; rows already stored
keep the fingerprint they were written with. Atlas derives issue IDs from the
fingerprint and keeps state on them, so its `IssueCoalescer` starts each new
issue from the issue the previous rules
(`Atlas.Engineering.Errors.Fingerprint.compute_legacy/1`) grouped the event
into: status, assignee, resolution and first sighting carry over and a resolved
one regresses on a newer event, while counts and impacted accounts start over.
All observed legacy origins are reconciled, including across batches. Ignored
or resolved status carries only when origins agree; conflicting statuses stay
unresolved. The earliest first sighting and a deterministic non-null assignee
survive. Repeated known origins do not overwrite later operator decisions.

### Issue lifecycle

`errors` covers at most its TTL, and the dashboard reads at most a day of it.
The `error_issues` flow (`error-issues.sql`) keeps `error_issue_hours` with no
TTL: one row per issue and hour it occurred in, with the first and last
occurrence in that hour and its count of distinct events. The flow recomputes
dirty hours as events arrive. After bootstrap the deploy runs
`ADMIN flush_flow('error_issues', true)` to recompute the retained day's hours,
including the whole leading hour, under the same execution lock as live flow
evaluations. Repeating recovery replaces the same sink keys without adding
counts or touching older history. Concurrent arrivals remain dirty for the
next evaluation; no independent repair writer can overwrite newer results.
This requires every flownode to support retained recomputation (the frontend
rejects an unacknowledged request during an upgrade). The optional flag only
supports ordinary, time-windowed batching flows with finite `EXPIRE AFTER`.
The one-argument flush drains dirty windows only; a recreated flow has none,
so that alone cannot repair an outage. Hours missed
while no flownode ran heal at the next deploy within a day. Events that arrive
more than a day late, and history from before the flow existed, are not in it.

```sql
-- Lifetime state of every issue.
SELECT "service", fingerprint, min(first_seen) AS first_seen,
  max(last_seen) AS last_seen, sum(events) AS events
FROM error_issue_hours GROUP BY "service", fingerprint;

-- New: first seen in the last day.
SELECT "service", fingerprint FROM error_issue_hours GROUP BY "service", fingerprint
HAVING min(first_seen) > now() - INTERVAL '1 day';

-- Regressed: seen in the last day after at least a week of silence.
SELECT "service", fingerprint FROM error_issue_hours GROUP BY "service", fingerprint
HAVING max(last_seen) > now() - INTERVAL '1 day'
  AND max(CASE WHEN last_seen <= now() - INTERVAL '1 day' THEN last_seen END)
    < now() - INTERVAL '8 days';
```

Pulse has no resolve action, so a regression here is a return after silence,
not after a resolution; Atlas keeps resolution state.

`sentry-errors-cases.json` holds grouping cases with Atlas's fingerprints,
derived by hand from the rules above. Atlas's `fingerprint_test.exs` and
`test-sentry-errors.mjs`, which the validate job runs against the pinned Pulse
image, both check them; change the pipeline and Atlas's `Fingerprint` together.
`test-sentry-errors.mjs` also checks that same-timestamp events are all kept,
that resends count once, and the issue rollup and its queries. To run it locally against a disposable Pulse:

```bash
PULSE_URL=http://127.0.0.1:4000 PULSE_AUTH=pilot:<password> node infra/helm/pulse/test-sentry-errors.mjs
```

## Release health

The same endpoint accepts Sentry's `session` and `sessions` items and writes
them to append-only `sessions` (`sessions.sql`): one row per individual session
update, or one per pre-aggregated group from server-mode SDKs. Readers select
the highest `seq` and then latest `updated` timestamp for each immutable
`service, release, environment, session_id, started` identity, independent of
replica or delivery order. `init: true` forces sequence zero; omitted sequence
and timestamp default to receipt's Unix milliseconds and UTC time respectively.
Exact replays count once. Aggregates get independent `aggregate-<uuid>` IDs:
they add counts and are never deduplicated by the distinct user/device ID.
`sessions` counts the sessions a row
stands for, and `errored`, `crashed`, `abnormal` and `unhandled` split them by
outcome; `distinct_id` is the SDK's user or device ID, hashed. Pulse never
creates this table itself, so sessions sent before the deploy installs it are
dropped. Crash-free rates per release:

```sql
WITH ranked AS (
  SELECT *, ROW_NUMBER() OVER (
    PARTITION BY service, "release", environment, session_id, started
    ORDER BY seq DESC NULLS LAST, updated DESC NULLS LAST,
      crashed DESC, abnormal DESC, unhandled DESC, errored DESC
  ) AS session_rank
  FROM sessions
  WHERE service = 'server' AND started > now() - INTERVAL '1 day'
)
SELECT "release",
  1 - CAST(sum(crashed + abnormal + unhandled) AS DOUBLE) / sum(sessions) AS crash_free_sessions,
  1 - CAST(count(DISTINCT CASE WHEN crashed + abnormal + unhandled > 0 THEN distinct_id END) AS DOUBLE)
    / count(DISTINCT distinct_id) AS crash_free_users
FROM ranked
WHERE session_rank = 1
GROUP BY "release"
```

The health counts break exact logical-clock/timestamp ties conservatively,
so a conflicting replay cannot erase a crash. Pre-upgrade rows lack ordering
metadata and rank behind sequenced updates; already-overwritten states cannot
be recovered. User rates count only rows with a distinct ID; Sentry treats `abnormal` as
crashed for its crash-free figures, and so does this query. The endpoint also
writes Sentry `log` items to `opentelemetry_logs` and spans to
`opentelemetry_traces` (see `pulse/FORK.md`), and limits each service to
`http.sentry_events_per_minute` error events per frontend (600 by default),
answering more with Sentry's `429` rate-limit headers.

## Symptoms inputs

The [Symptoms](../../../symptoms/README.md) evaluator reads these from database
`public`. Windows are UTC and start at `time_window`, the sink tables' time
index; counts are per window. The deployment smoke installs them alongside
`loki_otlp`: `loki-otlp.yaml`, then `symptoms.sql` once a trace exists, both
idempotent. The Flows' sink tables keep 35 days whatever the database TTL.
The evaluator reads as its own read-only `symptoms` user
(`symptomsReader`, from `PULSE_SYMPTOMS_READER/password`) and writes
nothing to Pulse. An earlier `symptoms_span_edges_1h` table is no longer
created or filled; drop it once no evaluator reads it.

**Log columns** on `opentelemetry_logs`, written by `loki_otlp` for every Loki
line (native OTLP rows leave them null):

| Column | Value |
| --- | --- |
| `service` | `service.name`, or `unknown` |
| `level` | `debug`, `info`, `warning`, `error`, `critical` or `unknown`: the stream's `level`, else a JSON line's `level` or a console line's `[level]` |
| `template_key` | `code:<16 hex>`, a hash of the logger call site when the line's metadata names it (OTel `code.function`, `code.filepath`, `code.lineno`; Elixir `mfa`, `module`, `function`, `file`, `line`); else `text:<16 hex>`, a hash of the tracing `target` and `template` |
| `template` | The message's first line, masked, at most 256 characters. A JSON line's message is its `message` (or `fields.message`); a console line's is what follows `[level] ` |
| `exception_fp` | For a line with an Elixir exception banner (`** (Type) message`) and stack trace, the `errors` table's `fingerprint` for the Sentry event of the same crash; null otherwise |

Before anything else, credentials become `<token>` in both `template` and the
stored `body`: the word after `Bearer`, JWTs (`eyJ….….…`), and runs of 32 or
more base64/base64url characters with upper case, lower case and a digit (with
`/` only alongside `+` or `=`, so paths survive). `exception_fp` still hashes
the raw line, so it keeps matching Sentry's fingerprint.

Masking replaces timestamps (`<ts>`), runner and temporary paths (`<path>`),
emails, UUIDs, Elixir terms such as `#PID<…>` and `#Ecto.Changeset<…>`
(`<term>`), bare PIDs, maps and structs up to three levels deep (`<map>`),
quoted strings, IPv4 and IPv6 addresses, hex of 8 or more characters with a
digit and `0x…` (`<hex>`), and numbers (`<n>`). A number after `status`,
`http`, `code`, `errno`, `sqlstate`, `error`, `exit status`, `exit code` or
`HTTP/1.1` is kept, and so are codes inside words (`E1001`, `v2`). Words are
never masked, so a message that interpolates a name (an account handle) gets
one template per name.

The server's Loki handler sends no call-site metadata today, so its keys are
`text:`. Adding `:mfa`, `:file` and `:line` to its `structured_metadata`
switches them to `code:` keys, which then change whenever the line moves. Pod
console logs arrive one line per entry, so only the server's own Loki handler
delivers a whole stack trace in one line. `exception_fp` follows
`sentry-errors.yaml`: type, the innermost frame's function and module
(`Elixir.<Module>`, or the bare Erlang module; the Elixir SDK marks no frame
in-app, so Atlas picks that frame too) and the exception message normalized the
same way. It covers `Sentry.capture_exception` and crashes the logger handler
reports as exceptions, not Rust panics.

**Flows** (batching mode). Each writes the sink table of the same name, whose
primary key is its non-count columns other than `time_window`; sinks also get
the Flow engine's `update_at` column.

| Flow and table | Window | Keys | Values |
| --- | --- | --- | --- |
| `symptoms_trace_counts_1m` | 1 min | `service_name`, `span_kind` (`SPAN_KIND_SERVER`, …), `span_name`, `service_version` (resource `service.version`, null when unset) | `span_count`, `error_count` (spans with `span_status_code = 'STATUS_CODE_ERROR'`) |
| `symptoms_trace_latency_5m` | 5 min | The same, plus `latency_bucket` | `span_count` |
| `symptoms_log_counts_1m` | 1 min | `service`, `level`, `template_key` | `line_count` |
| `symptoms_log_totals_1m` | 1 min | `service` | `line_count` |

`latency_bucket` is `floor(ln(duration in ms) / ln 1.1)` clamped to 0..115:
bucket `b` holds `[1.1^b, 1.1^(b+1))` ms, bucket 0 also everything under
1.1 ms, and bucket 115 everything from about 57.6 s. Both log Flows count only
lines with a `template_key`, that is, lines that went through `loki_otlp`.

Flows count rows written while they run. They do not backfill earlier data,
and rows written while the flownode is down (frontends log `Failed to insert
data into flownode`) are missing from their windows unless a later row lands in
the same window. Treat a missing window as unknown, never as zero. To repair a
range, run the Flow's own `SELECT` restricted to it and `INSERT` the result into
the sink, which overwrites rows with the same keys.

**Span edges.** A Flow cannot join, so the evaluator runs the read-only
`span-edges.sql` every hour, for the hour that ended at least 10 minutes
earlier, and keeps the result (keys `caller_service`, `caller_span_name`,
`callee_service`, `callee_span_name`; value `edge_count`) in its own database.
It counts each span whose parent is in the same trace and started at most an
hour before the window, by the child's start.

**Cost.** Frontends mirror every write to `opentelemetry_traces` and
`opentelemetry_logs` to the flownode and keep those tables off the bulk insert
path, and each Flow reruns its query over the windows that changed. The
span-edge query self-joins up to two hours of spans. None of this has been
measured at production volume; watch frontend and datanode memory and the
`pulse-flownode` pod after the first deploy. `DROP FLOW` on a `symptoms_*` Flow
stops its cost without touching ingest.

The flownode queries frontends on their internal gRPC listener (4010), which
does not authenticate; `pulse-internal` admits only Pulse's own pods to it.
`pulse-readiness.sh` does not gate server deploys on the flownode: ingest does
not depend on it.

## Rollback boundaries

Rolling back a collector change means pointing `k8s-monitoring` back at
whatever backend should receive writes. To send them back to Grafana Cloud,
follow the rollback in
[`pulse-grafana.md`](../k8s-monitoring/pulse-grafana.md#cloud-storage-stopped-on-november-17-2026).
Rolling back a backend change is a `helm rollback pulse` to an earlier revision.
Do not uninstall the backend or shrink its PVC as a rollback shortcut. Pulse
data is not copied between releases, and historical objects are neither
imported nor deleted.

Two errors changes outlive a rollback. `errors` stays append-only (Pulse
refuses to turn it off), so a server from before distinct counting counts an
SDK's resends twice. The `error_issues` flow and its table stay in metadata; on
a chart without the flownode the flow does not run, and the next deploy that
runs one recomputes the last day.

## Storage probe

The backend deploy's storage probe does not depend on any release's Secret: it
creates a run-scoped ExternalSecret from the rendered chart's
`PULSE_S3_CREDENTIALS` references and deletes it afterwards, so it works before
the first install.

## Validation

```bash
bash infra/helm/pulse/test-managed.sh
node --test .github/scripts/pulse-storage.test.mjs
node --test .github/scripts/pulse-readiness.test.mjs
PULSE_URL=http://127.0.0.1:4000 PULSE_AUTH=pilot:<password> node infra/helm/pulse/test-sentry-errors.mjs
PULSE_URL=http://127.0.0.1:4000 PULSE_AUTH=pilot:<password> node infra/helm/pulse/test-symptoms-inputs.mjs
helm repo add grafana https://grafana.github.io/helm-charts
helm dependency build infra/helm/k8s-monitoring
bash .github/scripts/pulse-collectors.test.sh
```

CI also lint/renders the staging Grafana chart and runs its Python tests in an
isolated venv with PyYAML; no dependency is added to Pulse runtime. Local binary
protocol tests do not prove S3 behavior, capacity, live ingress/NetworkPolicy,
browser/tailnet access, or any staging/canary/production rollout.
