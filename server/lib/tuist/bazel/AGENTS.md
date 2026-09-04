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
  in PostgreSQL without parsing Extensible Markup Language. The invocation
  completion event schedules an idempotent Oban job.
- The build processor waits for the completed invocation, combines all
  delivered targets and attempts into one shared test run, and stores sanitized
  `test.log` output as invocation logs.
- Tuist never pulls cache artifacts from Kura. Artifact delivery is bounded and
  best effort, so a lost diagnostic never affects a build or cache operation.

## Data handling

- `bazel_invocations` stores completed commands received from Kura.
- `bazel_invocation_logs` stores sanitized, ordered log chunks in ClickHouse.
- `bazel_test_invocations`, `bazel_test_results`, and `bazel_test_summaries`
  durably stage bounded raw test results in PostgreSQL until processing
  succeeds; a daily job removes any records older than 90 days.
- Test cases and failure details derived from JUnit reports use the shared
  `test_runs` data model and retain the Bazel invocation identifier.
- Update `server/data-export.md` and the public retention guide whenever a
  retained field, table, or retention period changes.
