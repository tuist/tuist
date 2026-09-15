# Tuist Helm Chart

This chart deploys the Tuist server, cache service, processor, and optional server-owned public web workloads, with support for either embedded or external infrastructure dependencies.

Noora Storybook ships from the standalone `infra/helm/noora-storybook/` chart so it can keep an independent deployment workflow.

## Infrastructure dependencies

- `postgresql`
- `clickhouse`
- `objectStorage`
- `observability`

Each dependency defaults to `embedded` (deployed within the chart). To use an external provider instead, set its `mode` to `external` and configure the connection details under the corresponding section in `values.yaml`.

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

## Public dashboard crawler protection

Managed staging, canary, and production enable
`server.publicPageChallenge.enabled`. The chart sets
`TUIST_PUBLIC_PAGE_CHALLENGE_ENABLED` explicitly; the default is false for
self-hosted installations. Anonymous account, project, and preview dashboard
visitors must complete Turnstile before the server renders the page or mounts
its LiveView. Signed-in visitors and sessions verified within the four-hour
freshness window pass through. Marketing, docs, APIs, and native preview
downloads remain outside this application gate.

The dashboard gate is independent of `server.turnstile.enabled`, which controls
signup verification. Either gate retains the shared Turnstile keys in the
server's ExternalSecret when `server.turnstile.secretsFrom` is `eso`. Managed
environments already use a real widget whose hostname allowlist includes
staging.tuist.dev, canary.tuist.dev, and tuist.dev. Do not use always-passing
test keys for the managed dashboard gate.

Public visibility sets `x-tuist-public: 1` for edge rate limiting, but does not
enable indexing. Dashboard responses retain `X-Robots-Tag: noindex, nofollow`,
consistent with the router-derived robots.txt disallow entries. The legacy
Cloudflare rule in `infra/flux/cloudflare-config/custom-firewall-rules.yaml`
covers selected Tuist projects, including `/tuist/kura`; keep it enabled until
the general application gate has been verified in production.

### Rollout and verification

1. Rehearse on staging, then use the normal canary/acceptance/production deploy
   sequence. Verify that the server Deployment renders
   `TUIST_PUBLIC_PAGE_CHALLENGE_ENABLED=1` and the Turnstile ExternalSecret is
   ready. Check that `public_page_challenge_kill_switch` is not enabled.
2. In a fresh browser session, open a public project's test-detail URL and a
   public account dashboard. Both must redirect to `/turnstile-challenge`
   before rendering dashboard data. Solve the widget and confirm that the
   original path and query string are restored. Confirm signed-in access and
   subsequent verified navigation still work.
3. Check `X-Robots-Tag: noindex, nofollow` on both challenged and successfully
   rendered dashboards, plus `x-tuist-public: 1` for public pages. Check that
   marketing/docs remain indexable and native preview downloads do not receive
   a challenge. The focused server suites cover the HTTP and LiveView gates.
4. Check the `public-dashboard-bot-protection` CloudflareCustomRule in the
   management cluster: its observed generation must be current and `Ready`
   true. Flux readiness alone does not prove the edge rule was reconciled.
5. Inspect fresh Faro measurements for the Chrome 145 / 1366×1366 crawl and
   the Linux / 1919×992 cohort. Previously ingested measurements remain in the
   six-hour and 24-hour alert windows until they expire.

For an immediate application rollback, enable the existing
`public_page_challenge_kill_switch` runtime flag; persist a rollback by setting
`server.publicPageChallenge.enabled: false` in the affected managed values and
redeploying. This leaves signup verification, noindex headers, and the legacy
edge protection in place. Revert the Kura path addition in git if the edge
change itself needs rollback; dashboard edits in Cloudflare are reconciled
back to the declared rule.

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
`KURA_ANALYTICS_SERVER_URL` pointing to the server's internal Service. Both
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
