# Cache (Context)

This context owns cache entries and CAS analytics ingestion.

## Responsibilities
- Create cache entries in ClickHouse via `IngestRepo`.
- Query cache entries by CAS ID and project ID.
- Batch insert CAS analytics events (upload/download sizes).
- Resolve cache grants and billing refusals through `Billing` entitlement checks, not live billing subscriptions. Expired payment grace removes paid grants and reports payment failure once the applicable Air allowance is exhausted. Existing cache JWT grants remain snapshots until normal token expiry.

## Boundaries
- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.

## Guardrails
- Cache entries and CAS analytics are stored in ClickHouse; update `server/data-export.md` on schema changes.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
