# Xcode (Context)

This context owns Xcode graph ingestion and analytics.

## Responsibilities
- Ingest Xcode graphs and targets into ClickHouse buffers.
- Compute selective testing and binary cache analytics for runs.
- Provide counts for cache hits/misses and selective testing hits.

## Boundaries
- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.

## Guardrails
- Xcode graph data is analytics data; update `server/data-export.md` on schema changes.
- Capture `xcode_graphs.modules_count` from distinct project/module pairs across every reported target, including noncacheable targets, while preparing the complete graph payload. Store this with the server-attributed project ID in the graph header so partial target-buffer arrival cannot imply removals and client event-ID collisions cannot mix tenants. The project-leading projection covers new headers only; do not materialize/backfill historical snapshots. Empty graphs record zero; legacy graphs stay NULL, with no retrospective inference/backfill. This is a reported workspace snapshot, not an exhaustive repository inventory. Graph retention remains 30 days; `Tuist.BuildEntities.default_branch_module_counts/3` supplies independently bounded default-branch dashboard state.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`

- Store effective destinations separately from declared graph metadata. For empty hashed destinations, use the owning command event's CLI version (4.208.0 stable onward) to distinguish known empty inputs from historical absence; nullable new components distinguish unavailable inputs from known absence (empty strings).
