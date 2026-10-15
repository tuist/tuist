# App Builds (Context)

This context owns business logic and data related to app builds and previews.

## Responsibilities
- Create previews and app builds, and link builds to previews.
- Find latest previews by bundle identifier/branch/track and supported platforms.
- List previews with pagination and distinct bundle identifiers. `list_preview_tracks/1` independently lists all nonempty tracks for one project, grouped with the column's case-insensitive semantics, choosing a deterministic display spelling and sorting by track.
- Previews can carry optional plain-text `release_notes` (up to 10,000 characters). Notes are metadata, never part of preview identity: old and new clients must group the same build even when only one supplies notes. The first nonblank notes are retained; filling a reused preview uses an atomic `release_notes IS NULL` update so competing replicas cannot overwrite them. Omitted, null, empty, and whitespace-only notes never clear stored notes. Notes follow the preview's existing retention and export rules.
- Apply supported-platform filters before choosing distinct bundle identifiers, so a newer device-only upload cannot hide an older simulator build.

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
