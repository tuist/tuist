# Tuist Helm Chart

This chart deploys the Tuist server, cache service, processor, and optional server-owned public web workloads, with support for either embedded or external infrastructure dependencies.

Noora Storybook ships from the standalone `infra/helm/noora-storybook/` chart so it can keep an independent deployment workflow.

## Infrastructure dependencies

- `postgresql`
- `clickhouse`
- `objectStorage`
- `observability`

Each dependency defaults to `embedded` (deployed within the chart). To use an external provider instead, set its `mode` to `external` and configure the connection details under the corresponding section in `values.yaml`.

Embedded object storage uses the [Cool Labs community build of MinIO](https://github.com/coollabsio/minio), pinned to a release and multi-architecture digest. The upstream `quay.io/minio/minio` and `quay.io/minio/mc` images no longer allow anonymous pulls. Both the server and bucket initialization Job use the same image, which includes the `mc` client and shell. Override `objectStorage.embedded.image` and `objectStorage.embedded.mcImage` to use your own builds; keep the server's MinIO entrypoint and the initializer's `/bin/sh`, `mc`, and `sleep` available. This restores image availability; the community build does not provide an ongoing upstream security-support commitment. Managed environments use external object storage and do not run these images.

The Tuist server can use Azure Blob Storage for server-owned artifacts by setting `server.storage.provider: azure_blob` and filling `server.azureBlob.*`. The top-level `objectStorage` dependency remains S3-compatible because optional workloads such as the cache service and registry mirror still use S3-compatible APIs. For Azure-only deployments with those workloads disabled, set `objectStorage.mode: external` and leave the external object-storage endpoint and credentials empty to avoid deploying the embedded MinIO StatefulSet.

External PostgreSQL with an existing Secret:

```yaml
postgresql:
  mode: external
  external:
    port: 5432
    database: tuist
    existingSecret: tuist-postgresql
    existingSecretKeys:
      host: host
      username: username
      password: password
```

The chart reads `host`, `username`, and `password` from the named Secret and
builds `DATABASE_URL` through Kubernetes env-var substitution, so the password
does not appear in the rendered manifest. The Secret value for `password`
should be URL-safe because it is interpolated into a database URL.

## Artifact retention

Artifact cleanup is disabled by default. Opt in by setting positive retention
windows, in days, for the artifact families you want the server to clean from
object storage. Omitted families remain untouched.

```yaml
server:
  artifactRetentionDays:
    cacheArtifacts: 30
    appPreviews: 30
    buildArchives: 60
    runArtifacts: 30
    testAttachments: 30
    shardBundles: 14
```

## Kura analytics

Managed environments enable `kuraController.analytics.enabled`. The chart
syncs `CACHE_API_KEY/password` from the same secret store used by the server
into `kura-shared-secrets` as `KURA_ANALYTICS_SIGNING_KEY`, alongside
`KURA_ANALYTICS_SERVER_URL` pointing to the server's internal Service in
absolute form, so a Kura node outside the control plane's region does not
spend a WAN round trip per search domain resolving it. Both
values are needed: Kura otherwise accepts Bazel build events while leaving
analytics delivery disabled. This also enables cache-operation analytics
and Bazel test-artifact delivery.

The controller rolls Kura pods when the shared Secret changes. After rollout,
`kura_analytics_queue_capacity` should be positive (the default is 1000).
Run a Bazel build with `--bes_upload_mode=wait_for_upload_complete`, then
verify its invocation appears in Tuist and that
`kura_analytics_events_total_total{pipeline="bazel_invocations",result="sent"}`
increases. Successful upload to Kura alone does not prove server ingestion.
Events accepted while analytics were disabled are not retained for replay.

This automatic secret sync requires `server.config.managedSecrets` and stays
disabled by default for self-hosted installs. Those installs can supply both
runtime variables through `kuraController.sharedSecrets.data` or an externally
managed shared Secret, using the same signing key as their server.

## Local validation

Render manifests:

```bash
helm template tuist infra/helm/tuist
```

Install into a local kind cluster:

```bash
kind create cluster --name tuist
helm install tuist infra/helm/tuist
```

Run the same [K3s](https://k3s.io/) smoke profile used by the Helm workflow. The task creates a disposable [k3d](https://k3d.io/) cluster, renders the chart, runs a server-side dry run, installs the chart, and waits for the embedded dependencies:

```bash
mise -C infra run helm:k3s-smoke
```

This profile keeps the server Deployment rendered, but scales it to zero
because booting the production server image requires a Tuist license. It
validates that K3s accepts the chart resources and can run the embedded
PostgreSQL, ClickHouse, and MinIO dependencies with its default storage class.

To validate only the Helm render without creating a cluster:

```bash
mise -C infra run helm:k3s-smoke --render-only
```

Lint the chart:

```bash
helm lint infra/helm/tuist
```

## Shared pod settings

The `global` block contains shared settings that apply across workloads rendered by the chart.

- `global.commonLabels` adds extra labels to chart resources.
- `global.podLabels` adds extra labels to pod templates.
- `global.imagePullSecrets` configures registry credentials for every pod in the chart.
- `global.nodeSelector` and `global.tolerations` let you steer pods onto specific node pools.

Example:

```yaml
global:
  podLabels:
    environment: production
  imagePullSecrets:
    - name: ghcr-pull-secret
  nodeSelector:
    nodepool: apps
  tolerations:
    - key: dedicated
      operator: Equal
      value: apps
      effect: NoSchedule
```

## Workload identity

Use per-workload service accounts when you need Kubernetes RBAC or cloud workload identity for a specific Tuist component.

```yaml
cache:
  serviceAccount:
    create: true
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/tuist-cache
```

The chart keeps service accounts scoped to the application workloads that need them:

- `server.serviceAccount` applies to the Tuist server deployment and migration job.
- `cache.serviceAccount` applies to the cache deployment.

Embedded PostgreSQL, ClickHouse, and MinIO continue to use the namespace default service account unless you customize them separately.

## Compatibility overrides

Some cluster-specific fixes are intentionally opt-in:

- `cache.podSecurityContext` is empty by default. Set `fsGroup` only if your storage class needs it.
- `cache.nginx.clientMaxBodySize` defaults to `10m`, matching the cache application's module part size limit. Raise it only when the application limit is raised too.
- `cache.nginx.resources` is separate from `cache.resources` because the nginx sidecar is a distinct container. Set it explicitly in clusters with strict default LimitRanger policies.
- `cache.nginx.proxyConnectTimeout`, `cache.nginx.proxyReadTimeout`, and `cache.nginx.proxySendTimeout` default to `60s`. Increase them for slower links or larger uploads.
- `clickhouse.embedded.service.nativePort` defaults to ClickHouse's standard `9000` service port and can be overridden for mesh or port-allocation conflicts.
- `clickhouse.embedded.systemLogs.ttlDays` applies a TTL to embedded ClickHouse `system.*` log tables such as `text_log`, `query_log`, `trace_log`, `metric_log`, and `part_log`. It is empty by default, leaving ClickHouse's unbounded retention untouched. Adopt it together with `supersededTables: delete`, in one `helm upgrade` — see below.
- `clickhouse.embedded.systemLogs.supersededTables` decides what happens to the `<name>_N` tables ClickHouse leaves behind when it supersedes a system log table, which it does on a retention change and on any ClickHouse upgrade that changes a system log schema. Defaults to `ignore`; `delete` drops them after each `helm upgrade`. There is no option to copy the rows back into the live table, because a ClickHouse upgrade changes the schema. A generation keeps whatever retention the live table had when it was superseded, so the ones a later window change produces expire on their own, while the ones from the first adoption — or from a ClickHouse upgrade on an install that never set a TTL — keep their rows indefinitely. ClickHouse never drops the tables themselves, so they accumulate either way.
- Setting `ttlDays` on an install that already has data is a one-time, one-way step, which is why it is not defaulted. Any value at all makes the table definitions stop matching, so ClickHouse renames each declared table aside and starts a fresh one. The generation it leaves behind holds every row accumulated so far and carries no TTL, so under `supersededTables: ignore` it is stranded permanently and the new window only bounds rows written from then on. Set both values in the same upgrade to get the intended end state:

  ```yaml
  clickhouse:
    embedded:
      systemLogs:
        ttlDays: 14
        supersededTables: delete
  ```

  That upgrade is self-contained because moving `ttlDays` from blank to set adds the drop-in mount, which rolls the StatefulSet: ClickHouse restarts, supersedes the tables, and the post-upgrade Job then drops them. It relies on the ClickHouse pod being rolled before hooks run, so deploy with `helm upgrade --wait`. Without it the generations appear after the Job has already looked and are reclaimed by the next `helm upgrade` instead.
- `clickhouse.embedded.systemLogs.level` controls the embedded ClickHouse server logger and `system.text_log` level. It defaults to `information`; use verbose levels like `debug` or `trace` only while investigating ClickHouse itself.
- Neither `clickhouse.embedded.systemLogs.ttlDays` nor `level` reaches a running pod on its own. Both drop-ins are `subPath` mounts, which Kubernetes does not update in place, and the chart does not roll the StatefulSet when its ConfigMap changes, so an edit applies the next time the ClickHouse pod restarts. Toggling `ttlDays` between blank and set is the exception, because the volume mount itself is conditional. The same delay means an upgrade that only edits these values produces no superseded tables for `supersededTables: delete` to reclaim during that upgrade; the generations appear at the later restart and are collected by the next `helm upgrade`.
- `clickhouse.external.pingUrl` lets the migration job wait for an external ClickHouse instance through a dedicated `/ping` URL when `clickhouse.external.url` includes a database path.

External ClickHouse example:

```yaml
clickhouse:
  mode: external
  external:
    url: http://user:password@clickhouse.example.com:8123/tuist
    pingUrl: http://clickhouse.example.com:8123/ping
```

Embedded compatibility override example:

```yaml
cache:
  nginx:
    clientMaxBodySize: 10m
    proxyReadTimeout: 300s
    proxySendTimeout: 300s
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 1
        memory: 512Mi
  podSecurityContext:
    fsGroup: 990

clickhouse:
  embedded:
    service:
      nativePort: 9100
    systemLogs:
      ttlDays: 7
      level: warning
```

## Scaling the server

Enable `server.cluster.enabled` before adding web replicas or enabling autoscaling. The chart rejects multiple replicas when discovery is disabled. Each web node is named `<applicationName>@<pod-address>` and libcluster discovers peer addresses through the release's headless service, including pods that are still starting. This works for both hosted and self-hosted installations.

The chart creates one `<release>-tuist-server-cluster` Secret containing a shared Erlang cookie. It reuses that value on upgrades through Helm's `lookup`. For deployment tools that render charts offline, supply a pre-existing Secret through `server.cluster.cookieExistingSecret` and `server.cluster.cookieExistingSecretKey`; offline rendering cannot recover an existing generated cookie. All replicas must use the same cookie, including during rolling upgrades. Do not rotate it independently on each pod. To rotate it, replace the shared Secret and restart all web nodes together during a maintenance window.

Offline `helm template` renders generate a fresh default cookie each time, so use the externally managed Secret option for reproducible manifests. Keep `cookieExistingSecretKey` stable across upgrades: changing it to a missing key in the generated Secret creates a new cookie. To rename the key without rotating credentials, first prepare an external Secret containing the same cookie under the new key, then update both Secret values together. Do not mix pods using different cookies.

Distribution uses port `server.cluster.distributionPort` (9100 by default) and Erlang's port mapper on 4369. When the server network policy is enabled, both ports are admitted only between this release's server pods. Keep these ports private. The release environment pins the Erlang distribution listener to the configured port; exposing only the port mapper is insufficient.

Processor fleets stay outside the web cluster. They consume durable database-backed jobs and enqueue broadcasts for the web tier. The Model Context Protocol endpoint is stateless, while Phoenix publish/subscribe, image locks, and marketing statistics use Erlang node connectivity. A surviving single web node remains useful; requiring a peer for readiness would make one failed node remove the other from service.

Check every running web pod with the release's `rpc 'Node.list()'` command. With two healthy replicas, each should list the other pod-address node. Check the cookie Secret reference and private network rules if the list stays empty. Check a rolling restart and a node departure before increasing traffic. The isolated local regression probe is:

```sh
cd server
MIX_ENV=test elixir --name scale_root@127.0.0.1 --cookie scale_verification \
  -S mix run --no-start test/cluster_scale_out.exs
```

Production rate limits continue using shared Valkey and reject requests if that store fails. Installations without Valkey retain approximate in-memory rate limits; publish/subscribe replication does not serialize admission. Security checks consult authoritative storage on every request. Prepaid balance invalidations are eventually consistent display updates, with expiration and cache clearing on membership changes as recovery paths.

Required test-ingestion writes are staged before acknowledgement and supervised optional tasks drain before ingestion buffers during graceful shutdown. Hard node loss can still discard buffered analytics before a flush; Erlang clustering does not turn local buffers into durable storage.
