# Tuist Helm Chart

This chart deploys the Tuist server, cache service, and processor, with support for either embedded or external infrastructure dependencies.

## Infrastructure dependencies

- `postgresql`
- `clickhouse`
- `objectStorage`
- `observability`

Each dependency defaults to `embedded` (deployed within the chart). To use an external provider instead, set its `mode` to `external` and configure the connection details under the corresponding section in `values.yaml`.

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
- `clickhouse.embedded.service.nativePort` defaults to ClickHouse's standard `9000` service port and can be overridden for mesh or port-allocation conflicts.

Example:

```yaml
cache:
  podSecurityContext:
    fsGroup: 990

clickhouse:
  embedded:
    service:
      nativePort: 9100
```
