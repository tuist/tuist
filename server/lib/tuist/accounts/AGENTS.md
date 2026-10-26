# Accounts (Context)

This context owns business logic and data related to accounts, users, organizations, roles, and auth tokens.

## Responsibilities
- `OIDCTrustPolicy` and `OIDCTrustPolicies` own reusable account-level workload identities. A matching policy grants account-wide CI access to all current and future projects, including projects created or transferred into the account after token issuance; do not enumerate project IDs or require a first project. Scope names and CRUD to the account, ignore submitted account IDs, and lock the account row to enforce 20 policies. There is no project association table. Project deletion or transfer leaves the identity intact; account deletion cascades its policies. Candidate lookup uses indexed `citext` account equality and audience prefiltering, returning each policy once regardless of project count. Fresh issuance through `oidc_account_by_grants/1` must recheck the policy ID, own key URL, issuer, audience, typed claims and selected account before issuing an `all_projects: true`, CI-only token. Existing project authorization must still require current account ownership. See `../oidc/AGENTS.md`.
- Manage accounts and organizations, including billing metadata and SSO credentials.
- `SSOLoginDomainTrust` resolves trust consistently for enrollment, email-based linking, discovery, settings validation and UI. Instances trust saved custom-provider domains by default, never arbitrary emails or fabricated DNS proofs. The internal default-off `TUIST_SSO_REQUIRE_LOGIN_DOMAIN_VERIFICATION` requires DNS proof when explicitly enabled by a deployment; managed Helm environments opt in. Without verification, organization administrators' providers have whole-account email-linking authority; there is no administrator allowlist or actor-option authorization layer. Preserve ordinary web/API authorization. Discovery prefers DNS proof, otherwise requires exactly one custom-provider claimant; Google stale domains are ignored. Trust stays in memory and adds no authorization queries. Short-circuit dynamic role checks on enrollment/default role before membership queries. Requiring DNS later must preserve unchanged saved policy flags so secret rotation remains possible. Policy changes require replica restarts and do not revoke identities or sessions.
- Sign-up reporting queries use explicit inclusive-start/exclusive-end creation periods and deterministic ordering, so adjacent hourly reports do not overlap.
- Issue and validate account/user tokens, device codes, and invitations.
- Resolve organization membership and role assignments.
- Own the WorkOS auth.md registration state machine, including service-signed identity assertions, browser claims, scheduled registration expiry, exchanged access-token records, audit events, and provider security events.
- The account usage worker refreshes metered cache egress and requests, then queues Air limit notifications through `Tuist.Billing.AirUsageNotifications` for the execution time, so delayed jobs cannot overwrite current-month counts with the previous month. `UserNotifier.air_usage_email/3` builds the HTML and plain-text email in the recipient’s preferred locale for delivery and previews.

## Boundaries
- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.

## Guardrails
- If changes add or modify stored customer data (users, organizations, tokens), update `server/data-export.md`.
- Keep the current `/agent/identity`, `/oauth2/token`, `/oauth2/revoke`, and `/agent/event/notify` behavior aligned with the published `/auth.md` document and authorization-server metadata.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`

- Account handles ending in `-staging` or `-canary` are reserved case-insensitively to prevent stable cache DNS collisions across environments. Existing suffixed handles keep regional endpoints until explicitly renamed. Stable managed endpoint responses preserve eligible custom endpoints and registered self-hosted URLs.
- Email-derived signup handles receive a numeric suffix when reserved, with the
  normal collision retries; explicit reserved handles remain invalid. Add custom
  endpoints only after stable hand-out succeeds, so absent managed instances
  still trigger provisioning and the existing client-specific fallback.
- Account handles are reserved for the account lifetime, including retired names. The database initializes and protects `kura_tenant_id`; do not cast or update it from account attributes. `Accounts.update_account/2` gates Kura account renames until compatible runtimes are deployed. See `../kura/AGENTS.md`.
