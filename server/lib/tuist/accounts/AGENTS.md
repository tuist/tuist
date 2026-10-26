# Accounts (Context)

This context owns business logic and data related to accounts, users, organizations, roles, and auth tokens.

## Responsibilities
- `OIDCTrustPolicy` and `OIDCTrustPolicies` own reusable account-level workload identities. A matching policy grants account-wide CI access to all current and future projects, including projects created or transferred into the account after token issuance; do not enumerate project IDs or require a first project. Scope names and CRUD to the account, ignore submitted account IDs, and lock the account row to enforce 20 policies. There is no project association table. Project deletion or transfer leaves the identity intact; account deletion cascades its policies. Candidate lookup uses indexed `citext` account equality and audience prefiltering, returning each policy once regardless of project count. Fresh issuance through `oidc_account_by_grants/1` must recheck the policy ID, own key URL, issuer, audience, typed claims and selected account before issuing an `all_projects: true`, CI-only token. Existing project authorization must still require current account ownership. See `../oidc/AGENTS.md`.
- Manage accounts and organizations, including billing metadata and SSO credentials.
- `SSOLoginDomainTrust` resolves DNS and self-hosted instance trust consistently for enrollment, email-based linking, discovery, settings validation and UI. The default-off `TUIST_SSO_TRUST_UNVERIFIED_LOGIN_DOMAINS` trusts every custom provider's saved email domain, never arbitrary emails or fabricated DNS proofs. There is no administrator allowlist or actor-option authorization layer: opting in explicitly trusts all users able to create or administer organizations to configure identity providers with whole-account email-linking authority. Preserve ordinary organization authorization at web/API entry points. Discovery prefers DNS proof, otherwise requires exactly one custom-provider claimant; Google stale domains are ignored. Per-organization trust stays in memory and adds no authorization queries. Short-circuit dynamic role checks on the enrollment flag and default role before membership queries. Preserve unchanged saved policy flags across trust withdrawal so secret rotation remains possible. Instance policy requires replica restarts, is not session revocation, and requires an operational configuration freeze and audit before enabling trust.
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
