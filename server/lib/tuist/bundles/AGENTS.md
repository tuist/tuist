# Bundles

## Responsibilities
- Create bundles with artifacts using `Ecto.Multi` and batch inserts.
- Fetch bundles and build nested artifact trees in memory.
- Compute install size deviations and list distinct bundles per project. Size-chart reads aggregate the latest bundle per time bucket in ClickHouse instead of materializing raw history. `project_app_bundle_options/1` returns at most 50 names and their latest supported platforms for the cached public overview, without loading full bundle structs.
- Bundle growth thresholds use exactly one of `deviation_percentage` or integer `deviation_bytes`. Existing percentages are not converted. Dashboard absolute values use decimal MB (1,000,000 bytes), with byte-precise comparisons. Equality and decreases pass; missing sizes/baselines skip. Zero baselines skip percentage rules but are valid for absolute rules.
- Threshold baselines match the uploaded bundle by name, type, and at least one shared supported platform. The threshold job carries `type` and `supported_platforms` in its args; jobs without them evaluate against an unfiltered baseline.
- The absolute-threshold migration preserves existing rules and refuses rollback while absolute rules remain. Convert those rules explicitly before rolling back; never discard them or infer percentages. Finish rolling out the new server code before creating absolute rules. A code-only rollback also requires converting absolute rules first: older workers do not recognize the byte column and would silently pass them. Percentage rules remain compatible with both versions.
- Decide who may accept a size increase that exceeded a threshold, and record who did.

## Guardrails
- Approval state belongs in Postgres. `bundles` is a ClickHouse MergeTree, where updating a row is an asynchronous mutation.
