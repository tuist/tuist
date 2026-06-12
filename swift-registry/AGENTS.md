# Swift Registry Service

This directory contains the standalone Swift package registry service deployed at `https://swift-registry.tuist.dev`.

## Responsibilities
- Serve the Swift Package Registry API at the service root. The dedicated `swift-registry.tuist.dev` host identifies the service, so the routes carry no `/api/registry/swift/` prefix; the Cloudflare Worker that proxies legacy `tuist.dev/api/registry/swift/*` and `registry.tuist.dev/*` traffic strips/rewrites the prefix when forwarding.
- Mirror Swift package release metadata, source archives, and alternate manifests into the registry S3 bucket.
- Keep local disk copies hot for nginx `X-Accel-Redirect` responses.
- Run registry release sync, S3 transfer, eviction, and orphan cleanup workers.
- Publish registry download analytics back to the Tuist server webhook.

## Development
- Install dependencies with `mise run install`.
- Run tests with `mise run test`.
- Run formatting with `mise run format` or `mise run format --check`.
- Run Credo with `mise run credo`.

## Deployment
- The production host is `swift-registry.tuist.dev`.
- The registry bucket is configured with `S3_REGISTRY_BUCKET`.
- Release sync requires `REGISTRY_GITHUB_TOKEN`.
- The managed deployment is Kubernetes-based via `infra/helm/swift-registry`.
- Runtime secrets are synced through External Secrets Operator from 1Password.
- See `ROLLOUT.md` for the staged migration plan from cache-served registry
  traffic to this service.

## Related Context
- Cache service: `cache/AGENTS.md`
- Operational registry tasks against the cache-served registry:
  `mise/tasks/registry/`
- Operational registry tasks against the swift-registry service:
  `mise/tasks/swift-registry/`
- Kubernetes chart: `infra/helm/swift-registry/AGENTS.md`
- Shared Elixir utilities: `tuist_common/AGENTS.md`
