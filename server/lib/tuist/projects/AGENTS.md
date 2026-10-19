# Projects (Context)

This context owns project records, tokens, and account/project handle resolution.

## Responsibilities
- Resolve projects by handles, tokens (legacy and new), and slugs.
- List accessible projects based on account/org membership.
- Manage project tokens and VCS connections. Each connection has exactly one provider-specific installation: GitHub (`provider: 0`) or Origin (`provider: 1`). Installation validation is conditional on the selected provider; an omitted provider has its own required-field error, not a default GitHub installation requirement. Origin connections are created through `Tuist.Origin` after checking same-account ownership, account-update authorization, and live native-repository access.
- `FlyOIDCTrustPolicy` stores project-scoped Fly.io trust in an exact issuer, numeric organization ID, and application ID. Context reads match all three fields; policy deletion is scoped to the owning project. Policies cascade on project deletion and never infer authorization from a Fly token's repository or caller-supplied project ID.
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
