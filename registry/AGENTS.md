# Tuist Registry Service

This directory contains the standalone Tuist package registry service
deployed at `https://registry.tuist.dev`. The service is multi-ecosystem
by design: each ecosystem mounts its own protocol-compliant API surface
under a path prefix that names the ecosystem.

Today the only ecosystem is the **Swift Package Registry** (SwiftPM,
SE-0292), reachable at `/swift/*`. Future ecosystems (Maven, CocoaPods,
OCI container images, etc.) would land at `/<ecosystem>/*` and share the
service's CAS, S3 storage, sync pipeline, and analytics plumbing.

## Responsibilities
- Mount per-ecosystem protocol APIs under `/<ecosystem>/*`. Currently
  `/swift/*` for the Swift Package Registry.
- Mirror package release metadata, source archives, and protocol-specific
  manifests into the registry S3 bucket (`registry/<ecosystem>/...`).
- Keep local disk copies hot on the pod PVC for nginx
  `X-Accel-Redirect` responses.
- Run release sync, S3 transfer, eviction, and orphan cleanup workers.
- Publish download analytics back to the Tuist server webhook.

## Code layout
- `lib/tuist_registry/` — generic plumbing shared across ecosystems
  (CAS, S3, SQLite buffers, Oban workers for transfers/eviction/orphan
  cleanup, analytics circuit breaker, webhook client).
- `lib/tuist_registry/swift/` — Swift Package Registry subsystem
  (`SyncWorker` against the Swift Package Index, `ReleaseWorker` against
  GitHub zipballs, metadata format, key normalizer, locks, alternate
  manifests, repository URL parsing).
- `lib/tuist_registry_web/` — generic web layer (`UpController`,
  `Endpoint`, `Router`, error views).
- `lib/tuist_registry_web/controllers/swift/` — Swift Package Registry
  controller (`TuistRegistryWeb.Swift.RegistryController`).

## Development
- Install dependencies with `mise run install`.
- Run tests with `mise run test`.
- Run formatting with `mise run format` or `mise run format --check`.
- Run Credo with `mise run credo`.

## Deployment
- The production host is `registry.tuist.dev`.
- The registry bucket is configured with `S3_REGISTRY_BUCKET`.
- Release sync requires `REGISTRY_GITHUB_TOKEN`.
- The managed deployment is Kubernetes-based via `infra/helm/registry`.
- Runtime secrets are synced through External Secrets Operator from 1Password.
- See `ROLLOUT.md` for the staged migration plan from cache-served
  registry traffic to this service.

## Related Context
- Cache service: `cache/AGENTS.md`
- Operational tasks against the legacy cache-served registry:
  `mise/tasks/cache-registry/`
- Operational tasks against this service: `mise/tasks/registry/`
- Kubernetes chart: `infra/helm/registry/AGENTS.md`
- Shared Elixir utilities: `tuist_common/AGENTS.md`
