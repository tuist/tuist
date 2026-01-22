# Github (Context)

This context integrates with the GitHub API and GitHub App.

## Responsibilities
- Fetch installation repositories, users, comments, and repository content.
- Download source archives for tags and handle pagination/link headers.
- Provide retry logic and request headers for GitHub API calls.

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
