# Projects (Context)

This context owns project records, tokens, and account/project handle resolution.

## Responsibilities
- Resolve projects by handles, tokens (legacy and new), and slugs.
- List accessible projects based on account/org membership.
- Manage project tokens and VCS connections. Each connection has exactly one provider-specific installation: GitHub (`provider: 0`) or Origin (`provider: 1`). Installation validation is conditional on the selected provider; an omitted provider has its own required-field error, not a default GitHub installation requirement. Origin connections are created through `Tuist.Origin` after checking same-account ownership, account-update authorization, and live native-repository access.
- `OIDCTrustPolicy` stores project-scoped custom workload trust: name, exact issuer, explicit JWKS URL, audience and 1–10 exact scalar identity claims. Policies require a target account during exchange, cannot override built-in CI issuers, cascade on project deletion and ignore submitted project IDs. Names are project-unique and creation serializes on the project row to enforce a 20-policy cap. Unsigned account/issuer/claim hints only prefilter at most 21 candidates; fresh grant reads must recheck each surviving policy's key URL, issuer, audience, claim types and account before returning its project. See `../oidc/AGENTS.md`.
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
