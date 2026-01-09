# Billing (Context)

This context owns billing, plan management, and Stripe integration.

## Responsibilities
- Define plan metadata (Air/Pro/Enterprise) and pricing thresholds.
- Create Stripe customers, billing portal sessions, and manage subscriptions.
- Record usage-based metering events (e.g., remote cache hits).

## Boundaries
- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.

## Guardrails
- Billing data is customer data; update `server/data-export.md` for schema or usage changes.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
