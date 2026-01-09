# Result Bundle (Context)

This context models xcresult/action result bundle structures.

## Responsibilities
- Define schemas for action invocation records, test plans, and references.
- Parse and structure result bundle metadata for server-side processing.

## Boundaries
- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.

## Guardrails
- Result bundles are stored in object storage; update `server/data-export.md` when schema or keys change.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
