# Cache Action Items (Context)

This context owns cache action item tracking (per-project hashes).

## Responsibilities
- Insert cache action items idempotently (conflict on project/hash).
- Fetch and delete action items for a project.

## Boundaries
- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.

## Guardrails
- Cache action items are stored in Postgres; update `server/data-export.md` on schema changes.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
