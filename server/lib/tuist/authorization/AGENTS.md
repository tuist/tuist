# Authorization (Context)

This context owns authorization policies for server resources.

## Responsibilities
- Define LetMe policies for resources (runs, bundles, cache, registry, account, project, etc.).
- Gate access based on subject type (user, project, account token) and scopes.

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
