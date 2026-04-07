# Cache Repo Monitoring

This context owns the cache-specific wrappers around shared repo monitoring.

## Responsibilities
- Configure shared repo pool metrics for cache repos.
- Keep the reader/writer split for the local key-value SQLite database explicit in repo wiring and metrics labels.
- Keep cache repo labels and telemetry prefixes aligned with PromEx wiring.

## Boundaries
- Shared repo pool metric implementation belongs in `tuist_common/`.
- Repo startup and supervision wiring belongs in `cache/lib/cache/application.ex`.

## Related Context
- Parent cache domain: `cache/lib/cache/AGENTS.md`
- Shared helpers: `tuist_common/AGENTS.md`
