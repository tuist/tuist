# Gradle analytics

This context owns Gradle report ingestion, task rankings and execution graph analysis.

- `Tuist.Gradle` validates and buffers build/task reports. Write through `IngestRepo`/buffers and read through `ClickHouseRepo`.
- `Bottlenecks` scopes rankings, totals, time series, previous-period comparisons and history by the same project and comparable build filters. Task identity includes root project, build path, task path and task type. Summary totals are not limited by the ranking row cap; distinct task totals are computed across the whole period, not by summing time buckets.
- `task_executions` returns paginated individual task attempts with outcomes, observed durations, timestamps, and build project/tag metadata; build accounts are batch-preloaded for Ran by badges; search and sorting apply before pagination and retain the full task identity and build cohort.
- `ExecutionGraph` models dependencies and hard ordering; soft ordering is not a hard edge. Neighbor relationships use data dependencies only. Missing timings and partial/cyclic graphs never produce a numeric chain estimate.
- Chain analysis happens on read, not during ingestion; derived chain metrics and participation flags are not persisted.
- Graph ingestion is bounded to 20,000 nodes and 100,000 edges. Keep collector and server limits aligned.
- Cacheability summaries honor explicit execution telemetry, falling back to the reported boolean only for legacy builds. Hit-rate analytics divide total remote hits by total hits plus confirmed misses, using the same rule for each time bucket; never average bucket percentages. Empty intervals have a null rate. Cacheable tasks without remote lookups have a zero hit rate; non-cacheable and unknown tasks without lookups retain a null rate.
- Duration chart averages and percentiles aggregate individual executed tasks across the full comparison periods and within each time bucket, excluding cache hits and skipped work. Empty buckets have null averages and percentiles, not zero durations. Never derive period averages or percentiles by averaging bucket statistics.
- Remote misses require a confirmed lookup; use operation durations for transfer throughput. Cumulative task time is not elapsed build time saved.
- Schema changes require updating `server/data-export.md`. Existing Gradle tables retain data for 90 days.

Related: `gradle/AGENTS.md`, `server/lib/tuist_web/live/gradle_bottlenecks_live.ex`, `server/lib/tuist_web/live/gradle_execution_component.ex`.

- `Gradle.get_task/3` retrieves one execution with UUID validation and both project/build scoping; never expose task details by task ID alone.
