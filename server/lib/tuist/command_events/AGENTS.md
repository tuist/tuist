# Command Events (Context)

This context owns command event ingestion and analytics retrieval.

## Responsibilities
- Share the cache counting-window rule (calendar month or later free-tier reset) with Air usage notifications through `usage_counted_from/2`.
- Query and paginate command events from ClickHouse (including test runs).
- Resolve associated user/project metadata and normalize enums.
- Manage result bundle storage keys and signed download URLs.
- Enqueue command event ingestion into the buffer.
- `Event.changeset/1` captures recorded argument arrays before constructing the legacy space-joined string. `command_arguments_recorded` distinguishes unknown historical/legacy boundaries from a recorded empty array. Never split historical strings or infer effective generation scope from missing arguments. Keep the legacy string and its filters compatible; list hydration reads new columns from canonical `command_events`, not optimized index tables.

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
