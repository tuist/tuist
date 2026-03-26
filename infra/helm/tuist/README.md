# Tuist Helm Chart

This chart deploys the Tuist server, cache service, and processor, with support for either embedded or external infrastructure dependencies.

## Supported installation profiles

- `distributed`: application workloads are deployed by the chart and infrastructure dependencies are expected to be provided externally.
- `compact`: application workloads are deployed by the chart and infrastructure dependencies can be embedded in the same Helm release.

## Dependency capabilities

- `postgresql`
- `clickhouse`
- `objectStorage`
- `observability`

Each dependency can be configured independently as either `embedded` or `external` where applicable.

## Local validation

Render manifests:

```bash
mise exec helm -- helm template tuist infra/helm/tuist -f infra/helm/tuist/values-compact.yaml
```

Install into a local kind cluster:

```bash
mise exec kind -- kind create cluster --name tuist
mise exec helm -- helm install tuist infra/helm/tuist -f infra/helm/tuist/values-compact.yaml
```
