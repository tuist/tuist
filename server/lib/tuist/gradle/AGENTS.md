# Gradle analytics

This context owns Gradle report ingestion, task rankings and execution details.

- `Tuist.Gradle` validates and buffers build/task reports. Write through `IngestRepo`/buffers and read through `ClickHouseRepo`.
- `TaskAnalytics` scopes rankings, totals, time series, previous-period comparisons and history by the same project and comparable build filters. Task identity includes root project, build path, task path and task type. Summary totals are not limited by the ranking row cap; distinct task totals are computed across the whole period, not by summing time buckets.
- `task_executions` returns paginated individual task attempts with outcomes, observed durations, timestamps, and build project/tag metadata; build accounts are batch-preloaded for Ran by badges; search and sorting apply before pagination and retain the full task identity and build cohort.
- Cacheability summaries honor explicit execution telemetry, falling back to the reported boolean only when task cacheability is absent (stored as an empty string); explicit unknown cacheability stays unknown. Hit-rate analytics divide total remote hits by total hits plus confirmed misses, using the same rule for each time bucket; never average bucket percentages. Empty intervals have a null rate. Cacheable tasks without remote lookups have a zero hit rate; non-cacheable and unknown tasks without lookups retain a null rate.
- Duration chart averages and percentiles aggregate individual executed tasks across the full comparison periods and within each time bucket, excluding cache hits and skipped work. Empty buckets have null averages and percentiles, not zero durations. Never derive period averages or percentiles by averaging bucket statistics.
- Remote misses require a confirmed lookup; compute transfer throughput from bytes and positive remote download/upload operation durations for the same transfers, excluding missing timings; do not estimate it from task duration. Cumulative task time is not elapsed build time saved.
- Schema changes require updating `server/data-export.md`. Existing Gradle tables retain data for 90 days.

Related: `gradle/AGENTS.md`, `server/lib/tuist_web/live/gradle_tasks_live.ex`.

- `Gradle.get_task/3` retrieves one execution with UUID validation and both project/build scoping; never expose task details by task ID alone.

- Keep task telemetry limited to identity, cacheability, incremental status, and cache outcomes used by the Tasks UI, plus transfer durations needed by existing throughput widgets. Do not collect unused explanations, build options, or duplicate project paths.

- `Timeline` loads all timed tasks, configuration operations and transforms for the authorized build and project. Nullable `gradle_builds.started_at` is the report duration origin; legacy reports use the earliest recorded operation or machine timestamp and identify that fallback. Machine samples share this origin. Missing timestamps/outcomes are never inferred from upload time or overall build success. Existing source retention applies; no operation logs are collected.

- Keep the nearest real machine sample before the build origin when there are samples during the build. Its negative offset brackets the first displayed interval without inventing a reading at zero. Samples entirely before the build provide no timeline coverage.

- Step API/MCP queries normalize the three operation tables through a ClickHouse union with database filtering, ordering and pagination; detail lookups do not load the full timeline or machine samples. Legacy origins are computed from scalar minimum timestamps. The dashboard still loads all operations for the interactive timeline.
