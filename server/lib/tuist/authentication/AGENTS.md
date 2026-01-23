# Authentication (Context)

This context owns authentication flows and token handling.

## Responsibilities
- Resolve authenticated subjects from JWTs, user tokens, and account/project tokens.
- Refresh tokens while updating `preferred_username` claims.
- Encode/sign tokens with recent accessible project handles.

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
