# Pulse on GreptimeDB

Pulse is Tuist's GreptimeDB fork: its source is in [`pulse/`](../../../pulse/FORK.md)
and `pulse-release.yml` publishes it as `ghcr.io/tuist/pulse`. In each workload
cluster this chart runs it as the private `pulse` release in namespace
`observability`, behind Service `pulse` (`pulse.observability.svc.cluster.local:4000`).
Every resource is named `pulse` or `pulse-*`; Greptime's own config paths,
environment variables and WAL topic names are unchanged. The chart directory
keeps its old name until the code is renamed.

The chart pins the fork release in `values.yaml`, which must already be
published: push `pulse/` to main and let `pulse-release.yml` finish before
dispatching a deployment. Pushes and pull requests only validate; deploying
needs a `Pulse GreptimeDB Replacement` dispatch from main, and canary/production
dispatches need their protected-environment approval.

The legacy Elixir Pulse release was uninstalled from every workload cluster
before this release took over its name. The interim `greptimedb` release that
ran upstream GreptimeDB in staging and canary is replaced, not migrated: see
[Uninstalling the old greptimedb release](#uninstalling-the-old-greptimedb-release).

## Bootstrap prerequisites

These are desired configuration, **not a record of provisioned resources**:

- Preserve `tuist-pulso-{staging,canary,production}` and their bucket-scoped
  credentials. The historical bucket names are intentional; Greptime writes under
  its own `pulse/` prefix and never rewrites legacy Pulse objects (under
  `tenants/`, `auth/` and `.pulse/`) or the interim release's `greptimedb/` data.
- In each environment's `onepassword` ClusterSecretStore vault, provide
  `PULSE_TOKEN/password`, `PULSE_SECRET_KEY_BASE/password` and
  `PULSE_S3_CREDENTIALS` fields `access_key_id` and `secret_access_key`. Keep the
  existing values: collectors authenticate with the same token.
- Confirm the ESO store is ready, the CI environment has its usual
  `OP_SERVICE_ACCOUNT_TOKEN`, and the general pool has the requested capacity.
- The management cluster is separate: it still runs the last Elixir Pulse
  chart (1.39.0) through `infra/flux/pulse-management`, with its own private
  `tuist-pulse-management` bucket and the `PULSE_SECRET_KEY_BASE`, `PULSE_TOKEN`
  and `PULSE_S3_CREDENTIALS` items in the **`tuist-k8s-mgmt`** vault. Its
  collectors no longer write to it, and its source is gone, so it can be
  reconciled from the published chart but not changed. Removing it is a
  separate decision; its bucket history is kept either way.

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
| `pulse-etcd` | 3 | Dedicated metadata quorum, never the Kubernetes etcd |
| `pulse-kafka` | 3 | KRaft brokers/controllers holding the remote WAL |
| `pulse-metasrv` | 3 | Leader-elected through etcd; region failover enabled |
| `pulse-datanode` | 3 | Regions; local disk is a rebuildable cache |
| `pulse-frontend` | 2 | Authenticated HTTP API behind Service `pulse:4000` |

WAL topics use replication factor 3, `min.insync.replicas=2`, no unclean leader
election and no time-based retention; Greptime prunes them after flushing to
object storage. Greptime v1.3.0 produces WAL records with `acks=all` (its pinned
rskafka client sends `acks=-1`), so an acknowledged write is on at least two
brokers. Local-WAL failover (`allow_region_failover_on_local_wal`) stays off and
missing WAL entries are an error (`overwrite_entry_start_id = false`). Cluster
data lives under `pulse/distributed/` so it never mixes with a standalone
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

Production standalone sizing (CPU 1 / memory 2 GiB) no longer applies. The
capacity gate runs before installation and counts this release's running pods
once (as the planned replacement), so upgrading an installed cluster is not
refused for needing its own capacity twice. `pulse-readiness.sh` follows the
installed topology: it requires every cluster workload (etcd, Kafka, metasrv,
datanodes, frontends) to be Helm-owned, fully rolled out and Ready at its
minimum replica count, or the single standalone StatefulSet.
Each cluster workload restarts when its own rendered configuration changes, not
on unrelated value changes.

## Deployment order and gates

`Pulse GreptimeDB Replacement` accepts `environment=staging`, `canary` or
`production`; this selects the protected CI environment, kubeconfig vault, shared
observability concurrency lane and isolated `tuist-pulso-<env>/pulse/`
bucket/prefix. Namespace is always `observability`. Never read credentials into
agent context. Canary/production reject `inspect_readers` before loading
credentials. Grafana Cloud destinations are never changed by any of these steps.

Each environment moves in this order:

0. **Remove the interim release** (staging and canary only). Dispatch with
   `uninstall_greptimedb=true`; see below.
1. **Install or qualify the backend.** Dispatch with `dashboard=true`. Ownership,
   storage class, capacity, ESO, S3 privacy, lifecycle and isolated-prefix gates
   must pass before the install. The `PULSE_S3_CREDENTIALS` key must have
   `s3:GetLifecycleConfiguration` on its own bucket
   (`arn:aws:s3:::tuist-pulso-<env>`); unknown lifecycle access fails closed. Do
   not grant lifecycle-write or cross-bucket permissions, broaden IAM or bypass
   the probe. CI then applies `ALTER DATABASE public SET 'ttl' = '7d'` in
   staging/canary and **`'forever'` in production**, bootstraps native OTLP
   metrics/logs/traces and the `loki_otlp` pipeline (`loki-otlp.yaml`), and smoke
   tests dashboard reads, rejected dashboard mutation, rejected writer reads and
   unauthenticated rejection, then rereads the data after restarting every
   stateful component.
2. **Write to Greptime.** Deploy `k8s-monitoring` with its Greptime destinations.
   Server deploys refuse this until `pulse-dashboard-auth` is Ready with its
   ingest keys, because Alloy drops its whole config, Grafana Cloud included,
   when a referenced Secret is missing. Then dispatch with
   `dashboard=true,verify_telemetry=true`, which requires recent real Kubernetes
   metrics, non-CI logs and non-CI traces. Idle workloads fail closed: generate
   traffic rather than accepting the synthetic smoke.

Staging dispatches with `dashboard=true` also install `greptime-grafana-staging`
from the `greptimedb-grafana` chart. Validate its tailnet/browser/data boundary
separately; Helm readiness is not evidence of it.

`inspect_readers=true` (staging only) also reports serving images, the live
`tuist` account ID, configured reader enrollment and the Pulse flag. It prints
only numeric IDs and booleans; raw RPC output is withheld.

Product readers are configured declaratively in the `tuist` chart: staging reads
Greptime (`TUIST_PULSE_BACKEND=greptime`, database `public`, username `dashboard`);
canary and production have no enrolled reader. Logs and traces support literal
text search rather than LogQL/TraceQL.

## Routine deployments remain independent

The server's collector readiness gate (`pulse-readiness.sh`) follows the live
workloads. With no `pulse` release installed it passes, and collectors still
deploy to Grafana Cloud. Otherwise every workload of the installed topology must
be Helm-owned by `pulse`, fully rolled out and Ready, and run a published
`ghcr.io/tuist/pulse:<version>-tuist.<n>` image; legacy `pulso` writers still
fail closed. The observability concurrency lane serializes these dispatches and
routine collector upgrades.

## Authentication, schema and network

Existing `pulse-auth` pilot credentials are created once by CI and never
rotated/read back. Pilot is for CI qualification only. With `dashboard.enabled`,
ESO reads existing `PULSE_TOKEN/password` into a separate provider file containing
`dashboard:ro=<token>` and `tuist:wo=<token>`. The same Secret
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

## Rollback boundaries

Rolling back a collector change means pointing `k8s-monitoring` back at
whatever backend should receive writes. Grafana Cloud is unaffected either way.
Rolling back a backend change is a `helm rollback pulse` to an earlier revision.
Do not uninstall the backend or shrink its PVC as a rollback shortcut. Pulse
data is not copied between releases, and historical objects are neither
imported nor deleted.

## Uninstalling the old greptimedb release

Staging and canary ran upstream GreptimeDB as the interim `greptimedb` release.
Dispatch with `environment` and `uninstall_greptimedb=true` to remove it. That
runs only the `uninstall-greptimedb` job: no backend install and no collector
rollout. It refuses while the environment's `k8s-monitoring` values or live
`k8s-monitoring-*` ConfigMaps reference the release's Service or Secrets, or any
pod outside the release mounts its Secrets, because Alloy drops its whole
config, Grafana Cloud included, when a referenced Secret is missing. It then
runs `helm uninstall greptimedb --keep-history`, checks that its
`data-greptimedb-*` PVCs survived, and finishes with the routine readiness gate.
The PVCs, the CI-created `greptimedb-auth` Secret and the bucket's `greptimedb/`
objects stay until someone deletes them deliberately; the staging reader loses
the interim data, which only had a 7-day TTL.

The backend deploy's storage probe does not depend on any release's Secret: it
creates a run-scoped ExternalSecret from the rendered chart's
`PULSE_S3_CREDENTIALS` references and deletes it afterwards, so it works before
the first install.

## Validation

```bash
bash infra/helm/greptimedb/test-managed.sh
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
