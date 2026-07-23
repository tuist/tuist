# Registry Service

Standalone Phoenix service hosting Tuist's Swift Package Registry. Production
clients reach it through `https://tuist.dev/api/registry/swift`; the Worker
forwards that path to the standalone service.

## Endpoints

Swift Package Registry under `/api/registry/swift`:

- `GET /api/registry/swift` and `GET /api/registry/swift/availability` - Registry availability.
- `GET /api/registry/swift/identifiers?url=...` - Resolve a GitHub repository URL to registry identifiers.
- `GET /api/registry/swift/:scope/:name` - List available package releases.
- `GET /api/registry/swift/:scope/:name/:version` - Show release metadata, or the source archive when negotiated with `Accept: application/vnd.swift.registry.v1+zip`.
- `GET /api/registry/swift/:scope/:name/:version/Package.swift` - Download the package manifest.

The same Swift surface is also available under `/swift/*` for environments
that expose the registry service directly.

## Setup

```bash
mise run install
```

Development defaults to port `8091` and uses `S3_REGISTRY_BUCKET` or `tuist-development-registry`.

## Configuration
- `SECRET_KEY_BASE` - Phoenix secret key base.
- `PUBLIC_HOST` - Public host, for example `tuist.dev`.
- `PORT` - TCP port Phoenix binds (defaults to 4000).
- `S3_REGISTRY_BUCKET` - Registry metadata and artifact bucket.

Managed deployments use the `registry` component in `infra/helm/tuist`, so the
read frontend and the server-owned Swift package sync worker roll in the same
Helm release. The chart syncs read-side S3 credentials from 1Password through
External Secrets Operator. The registry pod itself runs stateless; Swift package
sync runs from the server image in `TUIST_MODE=swift_registry_sync`.

## Validation

```bash
mise run format --check
mise run credo
mise run test
MIX_ENV=prod mix compile --warnings-as-errors
```
