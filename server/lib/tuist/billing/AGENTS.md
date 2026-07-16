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

## Stripe Meter Contracts

- `remote_cache_hit` records the legacy cache-hit count.
- `cache_egress_byte` records public client egress delivered over the public Internet in bytes. Configure the Stripe meter with sum aggregation, `stripe_customer_id` as the customer mapping key, and `value` as the value key. Each immutable Kura rollup is submitted with its original window timestamp so Stripe preserves subscription boundaries. The meter can collect usage before a price is attached. Keep the `cache_egress_gigabyte` unit price in `Tuist.Billing` aligned with the Stripe price attached to this meter.
- Only events with the public traffic plane and `public_internet` network path contribute to `cache_egress_byte`. Private and unknown paths, peer replication, and customer-operated Kura nodes must never contribute.
- `kura_billing_events` records each Kura event after Stripe accepts it. Always exclude ledgered events before submission so delayed outbox deliveries are reconciled without billing later redeliveries twice.
- Kura billing is independent from Kura availability. `Tuist.FeatureFlags.kura_billing_enabled?/1` must guard meter submission, the billing usage surface, and attachment of prices listed under the optional `kura_usage` plan category. Customer-operated deployments never enable this flag.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
