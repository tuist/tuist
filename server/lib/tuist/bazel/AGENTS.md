# Bazel Invocation Insights

This boundary owns completed Bazel invocation records uploaded directly by the
Tuist command-line interface after it captures Bazel's
[Build Event Protocol](https://bazel.build/remote/bep) output. Kura serves only
remote-cache traffic.

## Boundaries

- `bazel_invocations` stores one completed Bazel command. It contains requested
  target patterns, command kind, result, duration, timestamps, Git branch and
  commit SHA, project-scoping metadata, and a sanitized command configuration
  (Bazel version, configuration names, compilation mode, and remote
  cache/execution enabled flags). It retains a bounded requested command and,
  when emitted by Bazel, structured original and effective command lines.
  Client-environment entries are omitted; sensitive values and local-path
  options are redacted on the client and again at ingestion. It can
  retain Build Event Protocol metrics for processor time, executed actions,
  loaded/configured targets, and loaded packages, plus an allowlisted coarse
  operating-system and processor-architecture label. It can also retain a
  bounded critical-path summary extracted on the client: total duration plus
  up to 25 sanitized action descriptions and durations. It can also retain a
  bounded build timeline derived from the profile: up to eight anonymous work
  lanes and 180 sanitized spans with relative timings and a coarse category.
  It never stores the raw Bazel profile, thread identifiers or names, host
  name, unredacted command line, environment, local paths, or build artifacts.
- `bazel_test_results` stores one final test-target summary from Bazel's Build
  Event Protocol. It contains the target label, final status, duration, retry
  count, invocation identifier, completion timestamp, and project-scoping
  metadata, but never test output, logs, command arguments, or environment.
- `bazel_invocation_logs` stores ordered standard-output and standard-error
  chunks captured by `tuist bazel invoke`. Each invocation is bounded to 10
  megabytes, and the records are retained for 90 days. Logs are deliberately
  separate from aggregated analytics because they may include tool output and
  local source paths.
- Remote-cache observations remain in `Tuist.ReapiCache`. They are correlated
  only when their Bazel invocation identifier matches a completed invocation.
  Do not derive a command result or duration from cache traffic.
- Invocation and test-result data are stored in ClickHouse for 90 days.
  Retained fields and retention must stay documented in `server/data-export.md`
  and the public data-retention guide.
- Public readers are the Bazel REST endpoints and the Model Context Protocol
  tools. Keep their response schemas in sync with this context.
