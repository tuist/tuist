# Bazel Invocation Insights

This boundary owns completed Bazel invocation records delivered from Kura's
[Build Event Protocol](https://bazel.build/remote/bep) receiver.

## Boundaries

- `bazel_invocations` stores one completed Bazel command. It contains command
  kind, result, duration, timestamps, and project-scoping metadata, but never
  the full command line, environment, build artifacts, or test output.
- Remote-cache observations remain in `Tuist.ReapiCache`. They are correlated
  only when their Bazel invocation identifier matches a completed invocation.
  Do not derive a command result or duration from cache traffic.
- Invocation data is stored in ClickHouse for 90 days. Retained fields and
  retention must stay documented in `server/data-export.md` and the public
  data-retention guide.
- Public readers are the Bazel REST endpoints and the Model Context Protocol
  tools. Keep their response schemas in sync with this context.
