# Cache Repo Monitoring

This context owns cache repository monitoring and telemetry emission.

## Responsibilities
- Define PromEx plugins for cache database pool monitoring.
- Surface connection pool and connection lifecycle telemetry for cache repos.

## Boundaries
- Repo startup and supervision wiring belongs in `cache/lib/cache/application.ex`.
- Cache business logic belongs in `cache/lib/cache`.
- Shared repo-pool introspection helpers belong in `tuist_common/`.

## Related Context
- Parent cache domain: `cache/lib/cache/AGENTS.md`
- Shared helpers: `tuist_common/AGENTS.md`
