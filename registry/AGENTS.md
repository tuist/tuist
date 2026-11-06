# Package registry

Stateless read frontend. Swift package sync belongs to the server's
`Tuist.Registry.Swift.*` modules in `TUIST_MODE=swift_registry_sync`, not this app.
See `registry/README.md` for routes, configuration, and serving behavior.

Run from `registry/`: `mise run install`, `mise run test`,
`mise run format --check`, and `mise run credo`. Tests need no database.

## Contracts

- Keep this service free of databases, sync jobs, S3 writes, and disk caches.
  Hot metadata reads use strong-consistency requests and ETag-revalidated
  in-memory Cachex entries so repaired revisions cannot remain stale.
- Production clients use `https://tuist.dev/api/registry/swift` through the registry
  Worker, whose ingress origin is `registry.tuist.dev`. Preserve both
  `/api/registry/swift/*` and `/swift/*` for direct managed-service access.
- Source archives use `303` redirects to strongly consistent presigned S3 URLs,
  overriding content type to `application/zip`, without an existence probe.
  The object download is authoritative; lookup failures must not become false 404s.
  Serve manifests
  in-process under the registry origin; default `Package.swift` responses include
  alternate-manifest `Link` headers.
- Use `tuist_common/lib/tuist_common/registry/swift/` for S3 key normalization,
  repository URL parsing, and the metadata contract shared with the writer.
- Deploy through `infra/helm/tuist/` and
  `.github/workflows/server-deployment.yml`. Consult current per-environment values
  before changing writer enablement. The server owns the sole managed scheduled
  writer; cache registry cron stays disabled. Never run competing writers against
  the same bucket.
- The read frontend requires read access to its registry bucket. The separate
  writer also requires write access and GitHub credentials.

For smoke checks, request `/up`, `/api/registry/swift/availability` in production
(`/swift/availability` for direct managed access; expect `Content-Version: 1`),
and a known package with `Accept: application/vnd.swift.registry.v1+json`.
