# Cache (Context)

This context owns cache entries and CAS analytics ingestion.

## Responsibilities
- Create cache entries in ClickHouse via `IngestRepo`.
- Query cache entries by CAS ID and project ID.
- Batch insert CAS analytics events (upload/download sizes).

## Boundaries
- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.

## Guardrails
- Cache entries and CAS analytics are stored in ClickHouse; update `server/data-export.md` on schema changes.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
