# Command Events (Context)

This context owns command event ingestion and analytics retrieval.

## Responsibilities
- Query and paginate command events from ClickHouse (including test runs).
- Resolve associated user/project metadata and normalize enums.
- Manage result bundle storage keys and signed download URLs.
- Enqueue command event ingestion into the buffer.

## Boundaries
- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.

## Guardrails
- Command events and artifacts are stored in ClickHouse/S3; update `server/data-export.md` on schema changes.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
