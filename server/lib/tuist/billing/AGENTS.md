# Billing (Context)

This context owns billing, plan management, and Stripe integration.

## Responsibilities
- Define plan metadata (Air/Pro/Enterprise) and pricing thresholds.
- Create Stripe customers, billing portal sessions, and manage subscriptions.
- Record usage-based metering events (e.g., remote cache hits).
- Create and read Stripe billing credit grants (`Tuist.Billing.CreditGrants`), the money-denominated balance behind prepaid runner access. The runner-specific policy on top of it lives in `Tuist.Runners.Prepaid`.
- Air usage notifications run after the daily account usage refresh, at 80% and 100% of the independent remote-cache and runner-minute allowances. Runner usage reads `Tuist.Runners.Billing.compute_milliseconds/3` directly and truncates to baseline minutes, matching dispatch without its cached read. The configured limit comes from `Tuist.Runners.Allowance`, and active runner trials are excluded. Queue the highest reached threshold for all organization admins (or the personal account owner). A durable row per recipient, metric, threshold, and counting-period start records successful delivery to prevent resends after job pruning. Undelivered rows can be requeued when no active delivery job remains; a mid-month free-tier reset starts a new period only for cache usage. Runner notifications always reset on the UTC calendar month. Delivery workers recheck plan, role, period, and usage to suppress obsolete emails, send outside database transactions, and store the usage snapshot actually sent. Delivery is at least once: a crash after provider acceptance but before recording success can still cause a retry.

## Boundaries
- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.

## Guardrails
- Billing data is customer data; update `server/data-export.md` for schema or usage changes.
- Never blank a runner Price id in `stripe.prices.runners` once it has gone live. `configured_runner_price_ids/0` filters empty ids, so a later plan change would stop recognising the existing runner subscription item, delete it, and lose the cycle's accrued usage.
- Credit grants move money. Anything that creates one must stay idempotent against webhook redelivery and job retries.
- A runner trial is not a credit grant. It is the absence of a runner subscription item (`Tuist.Runners.Trials`), which is what makes runner usage unbillable open-endedly. Anything that builds subscription items must keep asking `Trials.on_trial?/1`, or a trial account silently starts being billed.
- The prepaid marker lives on the Stripe invoice *line*, not the invoice, and a grant is funded from the marked line's amount. A prepaid charge shares an invoice with that month's metered usage, so funding from `amount_paid` would convert the whole bill into runner credit.
- An invoice's `lines` are paginated and the webhook payload carries only the first few. Read them through `Tuist.Billing.Invoices.list_lines/1` rather than off the payload, or a prepaid line further down a busy bill goes unseen.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
