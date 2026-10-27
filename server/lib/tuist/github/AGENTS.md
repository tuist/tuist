# Github (Context)

This context integrates with the GitHub API and GitHub App.

## Responsibilities
- Fetch installation repositories, users, comments, and repository content.
- App release/page cache lookups use `Marketing.ReleaseMetadata` so pagination,
  cache waits and worker HTTP calls remain attributable to the page request.
- `InstallationAuthorization` exchanges a browser-bound github.com App OAuth code and checks the user's installation list for the exact, unsuspended deployment App installation, then requires ownership of its personal account or active organization-admin membership. Both Tuist-initiated and provider-initiated github.com setups use this proof. The github.com App needs Members read permission for the latter check; repository access alone must never authorize binding an entire installation. Never persist user access tokens or follow redirects/pagination URLs with them. Bound installation authorization to ten pages and five-second receive timeouts without retries. `Installations.attach/3` retains idempotent same-account installs, rejects transfers, and only updates pending registrations for the same canonical host; never retarget GHES credentials to github.com.
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
