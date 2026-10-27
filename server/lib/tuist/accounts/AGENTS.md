# Accounts

## Responsibilities
- `OIDCTrustPolicy` and `OIDCTrustPolicies` own reusable account-level workload identities. A matching policy grants account-wide CI access to all current and future projects, including projects created or transferred into the account after token issuance; do not enumerate project IDs or require a first project. Scope names and CRUD to the account, ignore submitted account IDs, and lock the account row to enforce 20 policies. There is no project association table. Project deletion or transfer leaves the identity intact; account deletion cascades its policies. Candidate lookup uses indexed `citext` account equality and audience prefiltering, returning each policy once regardless of project count. Fresh issuance through `oidc_account_by_grants/1` must recheck the policy ID, own key URL, issuer, audience, typed claims and selected account before issuing an `all_projects: true`, CI-only token. Existing project authorization must still require current account ownership. See `../oidc/AGENTS.md`.
- Manage accounts and organizations, including billing metadata and SSO credentials.
- Sign-up reporting queries use explicit inclusive-start/exclusive-end creation periods and deterministic ordering, so adjacent hourly reports do not overlap.
- Issue and validate account/user tokens, device codes, and invitations.
- Resolve organization membership and role assignments.
- Own the WorkOS auth.md registration state machine, including service-signed identity assertions, browser claims, scheduled registration expiry, exchanged access-token records, audit events, and provider security events.
- The account usage worker refreshes metered cache egress and requests, then queues Air limit notifications through `Tuist.Billing.AirUsageNotifications` for the execution time, so delayed jobs cannot overwrite current-month counts with the previous month. `UserNotifier.air_usage_email/3` builds the HTML and plain-text email in the recipient’s preferred locale for delivery and previews.

## Guardrails
- Keep the current `/agent/identity`, `/oauth2/token`, `/oauth2/revoke`, and `/agent/event/notify` behavior aligned with the published `/auth.md` document and authorization-server metadata.
- Account handles ending in `-staging` or `-canary` are reserved case-insensitively to prevent stable cache DNS collisions across environments. Existing suffixed handles keep regional endpoints until explicitly renamed. Stable managed endpoint responses preserve eligible custom endpoints and registered self-hosted URLs.
- Email-derived signup handles receive a numeric suffix when reserved, with the
  normal collision retries; explicit reserved handles remain invalid. Add custom
  endpoints only after stable hand-out succeeds, so absent managed instances
  still trigger provisioning and the existing client-specific fallback.
- Account handles are reserved for the account lifetime, including retired names. The database initializes and protects `kura_tenant_id`; do not cast or update it from account attributes. `Accounts.update_account/2` gates Kura account renames until compatible runtimes are deployed. See `../kura/AGENTS.md`.

- Okta/custom SSO requires a verified login email domain for discovery of nonmembers, automatic enrollment, and new-account creation. Never restore provider-identifier guessing or membership-only email linking. Existing linked members retain access and enforcement through stored roles; unlinked members confirm linking after signing in, with the existing SCIM-created-account exception. Preserve already-enabled settings while unverified, but require verification to turn policies on.
