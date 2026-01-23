# Qa (Context)

This context owns QA run schemas and artifacts (steps, recordings, screenshots).

## Responsibilities
- Define schemas and changesets for QA runs and related artifacts.
- Support QA workflows with launch arguments, logs, and recordings.

## Boundaries
- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.

## Guardrails
- QA run data is customer data; update `server/data-export.md` on schema changes.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
