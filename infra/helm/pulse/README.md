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
| `pulse-frontend` | 2 | Authenticated HTTP API behind Service `pulse:4000` |

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

Production's requests (`values-production.yaml`) total 8.6 CPUs and 23 GiB.
The chart's defaults size staging and canary, whose whole standalone backend
used about 600 MiB and 0.05 CPU, at 2 CPUs and 5.75 GiB. The install's capacity
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
   table (`errors.sql`, 90-day TTL in production, 7 days elsewhere) and the
   `sentry_errors` pipeline (`sentry-errors.yaml`; see [Errors](#errors)), and smoke
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
DSN never carries the dashboard's token. List an environment only once that item
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
stored text). The table is not append-only: retried events with the same issue
and timestamp merge on read.

`sentry-errors-cases.json` holds grouping cases with Atlas's fingerprints. Atlas's
`fingerprint_test.exs` and `test-sentry-errors.mjs`, which the validate job runs
against the pinned Pulse image, both check them; change the pipeline and Atlas's
`Fingerprint` together. To run it locally against a disposable Pulse:

```bash
PULSE_URL=http://127.0.0.1:4000 PULSE_AUTH=pilot:<password> node infra/helm/pulse/test-sentry-errors.mjs
```

## Rollback boundaries

Rolling back a collector change means pointing `k8s-monitoring` back at
whatever backend should receive writes. To send them back to Grafana Cloud,
follow the rollback in
[`pulse-grafana.md`](../k8s-monitoring/pulse-grafana.md#cloud-storage-stopped-on-november-17-2026).
Rolling back a backend change is a `helm rollback pulse` to an earlier revision.
Do not uninstall the backend or shrink its PVC as a rollback shortcut. Pulse
data is not copied between releases, and historical objects are neither
imported nor deleted.

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
helm repo add grafana https://grafana.github.io/helm-charts
helm dependency build infra/helm/k8s-monitoring
bash .github/scripts/pulse-collectors.test.sh
```

CI also lint/renders the staging Grafana chart and runs its Python tests in an
isolated venv with PyYAML; no dependency is added to Pulse runtime. Local binary
protocol tests do not prove S3 behavior, capacity, live ingress/NetworkPolicy,
browser/tailnet access, or any staging/canary/production rollout.
