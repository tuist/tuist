# Github (Context)

This context integrates with the GitHub API and GitHub App.

## Responsibilities
- Fetch installation repositories, users, comments, and repository content.
- Download source archives for tags and handle pagination/link headers.
- Provide retry logic and request headers for GitHub API calls.
- Resolve installation API endpoints through `VCS.installation_api_url/1`, including the optional GHES proxy override for token requests and authenticated API calls. Keep public-IP pinning and TLS hostname verification on the actual transport endpoint; browser URLs must not be replaced by proxy URLs.

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
