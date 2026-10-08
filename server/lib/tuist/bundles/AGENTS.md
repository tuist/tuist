# Bundles (Context)

This context owns bundle metadata and artifact trees.

## Responsibilities
- Create bundles with artifacts using `Ecto.Multi` and batch inserts.
- Fetch bundles and build nested artifact trees in memory.
- Compute install size deviations and list distinct bundles per project. Size-chart reads aggregate the latest bundle per time bucket in ClickHouse instead of materializing raw history. `project_app_bundle_options/1` returns at most 50 names and their latest supported platforms for the cached public overview, without loading full bundle structs.
- Bundle growth thresholds use exactly one of `deviation_percentage` or integer `deviation_bytes`. Existing percentages are not converted. Dashboard absolute values use decimal MB (1,000,000 bytes), with byte-precise comparisons. Equality and decreases pass; missing sizes/baselines skip. Zero baselines skip percentage rules but are valid for absolute rules.
- The absolute-threshold migration preserves existing rules and refuses rollback while absolute rules remain. Convert those rules explicitly before rolling back; never discard them or infer percentages. Finish rolling out the new server code before creating absolute rules. A code-only rollback also requires converting absolute rules first: older workers do not recognize the byte column and would silently pass them. Percentage rules remain compatible with both versions.
- Decide who may accept a size increase that exceeded a threshold, and record who did.

## Boundaries
- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.

## Guardrails
- Bundle and artifact data is customer data; update `server/data-export.md` on schema changes.
- Approval state belongs in Postgres. `bundles` is a ClickHouse MergeTree, where updating a row is an asynchronous mutation.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
