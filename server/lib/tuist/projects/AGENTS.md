# Projects (Context)

This context owns project records, tokens, and account/project handle resolution.

## Responsibilities
- Resolve projects by handles, tokens (legacy and new), and slugs.
- List accessible projects based on account/org membership.
- Manage project tokens and VCS connections. Each connection has exactly one provider-specific installation: GitHub (`provider: 0`) or Origin (`provider: 1`). Installation validation is conditional on the selected provider; an omitted provider has its own required-field error, not a default GitHub installation requirement. Origin connections are created through `Tuist.Origin` after checking same-account ownership, account-update authorization, and live native-repository access.
- `projects_by_oidc_grants/1` resolves explicit grants from account-owned workload identities. Reload policy key URL, issuer, audience and typed claims, then include only associated projects still owned by that policy's account. Unselected, future and transferred projects must never gain access. Policy storage and CRUD belong to `Accounts`; see `../accounts/AGENTS.md` and `../oidc/AGENTS.md`.
- Network-trusted report publishing belongs to instance runtime configuration, not persisted project settings. Keep normal project/build-system validation and project-scoped quotas without introducing a dashboard toggle.
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
