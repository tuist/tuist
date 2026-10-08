# Vcs (Context)

This context owns VCS models and GitHub App integrations.

## Responsibilities
- Model VCS entities (comments, users, installations, repositories).
- GitHub Enterprise installations retain `client_url` as the canonical browser/instance identity. Optional `api_url` is a full REST base URL for server-side transport only; resolve it with `VCS.installation_api_url/1`. Nil preserves existing URL derivation. Keep URL validation, signed registration state, and data-export documentation aligned.
- Provide workers for VCS-related background tasks.

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
