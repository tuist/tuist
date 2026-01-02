# Oauth (Context)

This context owns OAuth2 token/client handling (Boruta).

## Responsibilities
- Implement Boruta access token behavior with cache-backed lookups.
- Issue and revoke access/refresh tokens with custom client fetching.

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
