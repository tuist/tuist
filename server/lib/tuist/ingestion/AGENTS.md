# Ingestion (Context)

Server-side aliases over `TuistCommon.Ingestion.Buffer` and
`TuistCommon.Ingestion.Bufferable`. The runtime buffer and the schema
macro live in `tuist_common` so other Elixir services can reuse them;
`Tuist.Ingestion.Buffer` and `Tuist.Ingestion.Bufferable` are the thin
shims that let schemas here write `use Tuist.Ingestion.Bufferable`
without repeating `otp_app: :tuist, repo: Tuist.IngestRepo`.

## Responsibilities
- Present the shared ingestion buffer under the server-friendly namespace.
- Preload the `:tuist` + `Tuist.IngestRepo` defaults so schemas stay concise.
- `Batch.run/3` takes the report identity, stable plan timestamp and callback. It is request-local transport for immutable shard facts: flush per-schema encoded batches directly before publishing the report, bound staging by 8 MiB plus one row, and clear context on failure. Its deterministic UUIDv7s preserve replay and occurrence identity; their plan-time prefix is a partition hint, not the row's receipt month. It is not a shared coordinator or durable staging store. It adds physical `shard_report_id` metadata only to run-scoped fact tables, without changing legacy schema buffers. Keep its fact-source list and the shard-report migration/views aligned.

## Boundaries
- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.

## Guardrails
- If changes add or modify stored customer data, update `server/data-export.md`.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
