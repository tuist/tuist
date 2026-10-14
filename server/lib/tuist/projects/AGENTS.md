# Projects (Context)

This context owns project records, tokens, and account/project handle resolution.

## Responsibilities
- Resolve projects by handles, tokens (legacy and new), and slugs.
- List accessible projects based on account/org membership.
- Manage project tokens and VCS connections.
- A project connects to one forge repository. Origin links use stable repository IDs and account-owned installations; GitHub/OIDC handle queries default to the GitHub provider so same-named Origin repositories cannot join their authorization paths.
- Public sitemap queries select only account/project handles in bounded, deterministically ordered pages. Project visibility, not account visibility, controls inclusion.

## Boundaries
- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.

## Guardrails
- Project data is customer data; update `server/data-export.md` on schema changes.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
