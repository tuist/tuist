# Helm Charts

This node covers Helm assets under `infra/helm/`.

## Scope
- Umbrella and component charts for deploying Tuist services on Kubernetes
- Values for embedded vs external infrastructure dependencies
- Kubernetes manifests and helper templates for app services, data services, and observability

## Conventions
- Prefer one umbrella chart that models deployable capabilities, not implementation brands.
- Model infrastructure dependencies with capability names such as `objectStorage`, not provider names such as `minio`.
- Support both `embedded` and `external` dependency modes when practical.
- Keep local validation simple: `helm template` first, then a small-cluster install path such as `kind`.

## Related Context
- Parent infra context: `infra/AGENTS.md`
- Server runtime dependencies: `server/AGENTS.md`
- Cache runtime dependencies: `cache/AGENTS.md`
- Processor runtime dependencies: `processor/AGENTS.md`
