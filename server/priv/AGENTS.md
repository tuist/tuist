# Server Private Assets (Migrations, Seeds)

This directory contains database migrations and other private assets.

## Responsibilities
- PostgreSQL migrations: `server/priv/repo/migrations`
- ClickHouse migrations: `server/priv/ingest_repo/migrations`
- Marketing changelog entries: `server/priv/marketing/changelog`

## Guardrails
- If you change stored customer data, update `server/data-export.md`.
- Use `:timestamptz` for migration timestamps (per Credo rules).
- Add marketing changelog entries only for customer-facing product changes that are ready to announce.
- Do not add product changelog entries for ops-only, admin-only, internal rollout, infrastructure-only, or otherwise unannounced functionality.

## Related Context
- Business logic: `server/lib/tuist/AGENTS.md`
