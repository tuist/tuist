# Bazel Invocation Insights

This boundary owns Bazel invocation records and test artifacts received from
Kura. Kura terminates Bazel's [Build Event Service](https://bazel.build/remote/bep)
and forwards completed invocation summaries to the Tuist server. The server
does not expose a second Build Event Service listener.

## Test artifacts

- Kura recognizes only Bazel's conventional `test.xml` and `test.log` files
  referenced by Build Event Protocol test-result events.
- Kura queues per-attempt facts, per-target summaries, and artifact digests,
  reads at most 256 KiB per artifact under a background-memory reservation,
  and posts at most two files per result to the signed test-artifacts webhook.
  Results never wait for queue capacity. The completion marker waits for
  bounded capacity so accepted events remain ordered.
- The webhook performs bounded validation and upserts raw results and summaries
  in PostgreSQL without parsing Extensible Markup Language. Each invocation may
  stage at most 64 mebibytes of artifact bodies. The invocation completion event
  schedules an idempotent Oban job.
- The build processor consumes the dedicated `:process_bazel_tests` queue with
  its own concurrency limit, waits for the completed invocation for at most 15
  minutes, combines all delivered targets and attempts into one shared test
  run, and stores sanitized `test.log` output as invocation logs.
- Tuist never pulls cache artifacts from Kura. Artifact delivery is bounded and
  best effort, so a lost diagnostic never affects a build or cache operation.

## Data handling

- `bazel_invocations` stores completed commands received from Kura.
- `bazel_invocations` also stores bounded build metrics, retained action spans,
  critical-path summaries, and up to 20 custom build-metadata pairs. Kura keeps
  no more than 32 action spans or 32 critical-path actions for one in-flight
  invocation, and custom metadata keys and values are limited to 50 and 500
  bytes respectively.
- `bazel_invocation_logs` stores sanitized, ordered log chunks from bounded
  Build Event Protocol progress output and conventional test logs in
  ClickHouse.
- `bazel_test_invocations`, `bazel_test_results`, and `bazel_test_summaries`
  durably stage bounded raw test results in PostgreSQL until processing
  succeeds; an indexed, batched daily job removes any records older than 90
  days.
- Test cases and failure details derived from JUnit reports use the shared
  `test_runs` data model and retain the Bazel invocation identifier.
- Update `server/data-export.md` and the public retention guide whenever a
  retained field, table, or retention period changes.

- `Profile` ingests the complete Bazel JSON trace profile through Kura's signed profile webhook. `Timeline` prefers that profile and uses the bounded BEP summary only for older builds. Profile times use the native profile origin; CPU is measured in cores, memory in MiB and network in megabits/s before conversion for the UI. Never manufacture missing counters or rank away short events.
- `Action` stores BEP outcomes and sanitized diagnostic output, keyed by project, invocation, primary output and execution start. Step lists exclude logs; details and the dashboard fetch them separately. Ambiguous repeated-output actions are not assigned a guessed outcome.
- Profile and action rows expire after 90 days. Profile size limits reject the whole payload explicitly. Keep migration, data export and public retention documentation aligned.
- Native resource counters are one-second interval aggregates, timestamped at the bucket start. Attach `duration_ms` to each bucket, clipped to the timeline end, including when reading older stored profiles. Preserve the original offset and value; do not backfill the interval before collection or interpolate between aggregates.
- Remove trailing all-zero resource buckets only when they include zero total host memory, identifying Bazel's empty export padding. Apply this on ingestion and loading existing profiles. Preserve legitimate zero CPU/network readings and ambiguous CPU-only buckets; do not extend the previous measurement over the removed interval.

- On profile load, valid positive integer `TUIST_CPU_COUNT` invocation metadata converts native core usage to a percentage. Retain native readings and use cores when metadata is absent, invalid, or smaller than recorded usage; do not normalize against an observed peak or job count.
