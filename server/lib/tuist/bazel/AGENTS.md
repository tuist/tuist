# Bazel Invocation Insights

This boundary owns Bazel invocation records and test artifacts received from
Kura. Kura terminates Bazel's [Build Event Service](https://bazel.build/remote/bep)
and forwards completed invocation summaries to the Tuist server. The server
does not expose a second Build Event Service listener.

## Test artifacts

- Kura recognizes only Bazel's conventional `test.xml` and `test.log` action
  outputs after an action-cache write has committed.
- Kura queues metadata, reads at most 256 KiB under a background-memory
  reservation, and posts the content to the signed test-artifacts webhook.
  The cache write never waits for delivery.
- The webhook waits for the matching invocation, parses JUnit XML into the
  shared test-run data model, and stores sanitized `test.log` output as an
  invocation log. It uses Postgres receipts keyed by artifact identity to make
  retries idempotent.
- Tuist never pulls cache artifacts from Kura. Artifact delivery is bounded and
  best effort, so a lost diagnostic never affects a build or cache operation.

## Data handling

- `bazel_invocations` stores completed commands received from Kura.
- `bazel_invocation_logs` stores sanitized, ordered log chunks in ClickHouse.
- Test cases and failure details derived from JUnit reports use the shared
  `test_runs` data model and retain the Bazel invocation identifier.
- Update `server/data-export.md` and the public retention guide whenever a
  retained field, table, or retention period changes.
