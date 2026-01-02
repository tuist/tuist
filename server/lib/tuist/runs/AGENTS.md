# Runs (Context)

This context owns build/test run ingestion and analytics.

## Responsibilities
- Create builds/tests and ingest related data (files, targets, issues, cacheable tasks, CAS outputs).
- Query runs and test runs from ClickHouse with pagination.
- Broadcast build creation events via PubSub.

## Boundaries
- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.

## Guardrails
- Runs and analytics live in ClickHouse; update `server/data-export.md` on schema changes.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
