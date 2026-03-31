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
