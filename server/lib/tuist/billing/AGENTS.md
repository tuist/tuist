# Billing (Context)

This context owns billing, plan management, and Stripe integration.

## Responsibilities
- Define plan metadata (Air/Pro/Enterprise) and pricing thresholds.
- Create Stripe customers, billing portal sessions, and manage subscriptions.
- Record usage-based metering events (e.g., remote cache hits).
- Create and read Stripe billing credit grants (`Tuist.Billing.CreditGrants`), the money-denominated balance behind prepaid runner access and runner trials. The runner-specific policy on top of it lives in `Tuist.Runners.Prepaid`.

## Boundaries
- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.

## Guardrails
- Billing data is customer data; update `server/data-export.md` for schema or usage changes.
- Never blank a runner Price id in `stripe.prices.runners` once it has gone live. `configured_runner_price_ids/0` filters empty ids, so a later plan change would stop recognising the existing runner subscription item, delete it, and lose the cycle's accrued usage.
- Credit grants move money. Anything that creates one must stay idempotent against webhook redelivery and job retries.
- The prepaid marker lives on the Stripe invoice *line*, not the invoice, and a grant is funded from the marked line's amount. A prepaid charge shares an invoice with that month's metered usage, so funding from `amount_paid` would convert the whole bill into runner credit.
- An invoice's `lines` are paginated and the webhook payload carries only the first few. Read them through `Tuist.Billing.Invoices.list_lines/1` rather than off the payload, or a prepaid line further down a busy bill goes unseen.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
