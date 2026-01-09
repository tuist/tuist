# Accounts (Context)

This context owns business logic and data related to accounts, users, organizations, roles, and auth tokens.

## Responsibilities
- Manage accounts and organizations, including billing metadata and SSO credentials.
- Issue and validate account/user tokens, device codes, and invitations.
- Resolve organization membership and role assignments.

## Boundaries
- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.

## Guardrails
- If changes add or modify stored customer data (users, organizations, tokens), update `server/data-export.md`.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
