# App Builds (Context)

This context owns business logic and data related to app builds and previews.

## Responsibilities
- Create previews and app builds, and link builds to previews.
- Find latest previews by bundle identifier/branch/track and supported platforms.
- List previews with pagination and distinct bundle identifiers.

## Boundaries
- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.

## Guardrails
- If changes add or modify stored customer data, update `server/data-export.md`.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
