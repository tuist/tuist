# Accounts (Context)

This context owns business logic and data related to accounts, users, organizations, roles, and auth tokens.

## Responsibilities
- Manage accounts and organizations, including billing metadata and SSO credentials.
- Sign-up reporting queries use explicit inclusive-start/exclusive-end creation periods and deterministic ordering, so adjacent hourly reports do not overlap.
- Issue and validate account/user tokens, device codes, and invitations.
- Resolve organization membership and role assignments.
- Own the WorkOS auth.md registration state machine, including service-signed identity assertions, browser claims, scheduled registration expiry, exchanged access-token records, audit events, and provider security events.
- The account usage worker queues Air limit notifications through `Tuist.Billing.AirUsageNotifications` after refreshing usage for the execution time, so delayed jobs cannot overwrite current-month counts with the previous month. `UserNotifier.air_usage_email/3` builds the HTML and plain-text email in the recipient’s preferred locale for delivery and previews.

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
