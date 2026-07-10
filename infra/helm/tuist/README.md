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
- `clickhouse.embedded.systemLogs.ttlDays` applies a TTL to embedded ClickHouse `system.*` log tables such as `text_log`, `query_log`, `trace_log`, `metric_log`, and `part_log`. It defaults to `14`; set it to an empty value to keep ClickHouse's default unbounded retention.
- `clickhouse.embedded.systemLogs.level` controls the embedded ClickHouse server logger and `system.text_log` level. It defaults to `information`; use verbose levels like `debug` or `trace` only while investigating ClickHouse itself.
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
