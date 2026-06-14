# Swift Registry Service

Standalone Phoenix service for Tuist's Swift package registry mirror.

## Endpoints
- `GET /` and `GET /availability` - Registry availability.
- `GET /identifiers?url=...` - Resolve a GitHub repository URL to registry identifiers.
- `GET /:scope/:name` - List available package releases.
- `GET /:scope/:name/:version` - Show release metadata.
- `GET /:scope/:name/:version.zip` - Download the source archive.
- `GET /:scope/:name/:version/Package.swift` - Download the package manifest.

The old `/api/registry/swift` prefix is still routed for compatibility, but `https://registry.tuist.dev` serves the registry API at the root.

## Setup

```bash
mise run install
```

Development defaults to port `8091` and uses `S3_REGISTRY_BUCKET` or `tuist-development-registry`.

## Configuration
- `SECRET_KEY_BASE` - Phoenix secret key base.
- `PUBLIC_HOST` - Public host, for example `registry.tuist.dev`.
- `SERVER_URL` - Tuist server URL for analytics webhooks.
- `STORAGE_DIR` - Local registry artifact storage directory.
- `S3_REGISTRY_BUCKET` - Registry metadata and artifact bucket.
- `REGISTRY_GITHUB_TOKEN` - GitHub token used by sync workers.
- `TUIST_REGISTRY_SWIFT_API_KEY` - API key for server webhook calls. Falls back to `TUIST_CACHE_API_KEY`.

Managed deployments use `infra/helm/registry`. The Helm chart mounts PVCs for `/data` and `/storage`, and syncs runtime secrets from 1Password through External Secrets Operator.

## Validation

```bash
mise run format --check
mise run credo
mise run test
MIX_ENV=prod mix compile --warnings-as-errors
```
