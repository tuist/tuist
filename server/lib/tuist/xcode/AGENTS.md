# Xcode (Context)

This context owns Xcode graph ingestion and analytics.

## Responsibilities
- Ingest Xcode graphs and targets into ClickHouse buffers.
- Compute selective testing and binary cache analytics for runs.
- Provide counts for cache hits/misses and selective testing hits.

## Boundaries
- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.

## Guardrails
- Xcode graph data is analytics data; update `server/data-export.md` on schema changes.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
