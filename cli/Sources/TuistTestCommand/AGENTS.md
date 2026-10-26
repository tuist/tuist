# Test commands

This module owns test-run, case, suite, module and selection commands. Platform-specific test execution remains in the existing execution modules.

## Once sharding

- `tuist test once plan` exports a public portable Once plan, assigns its opaque batch IDs through module-granularity Tuist sharding, and uploads the original bytes in a plan-UUID-bound artifact. Never recreate or split Once's batches. Empty plans emit an empty matrix without creating a hosted plan.
- `run` downloads by exact hosted UUID and invokes Once's public scheduler once with all assigned IDs. An empty assignment must not invoke Once: omitting `--batch` means run everything. Each child inherits the hosted plan UUID as its external group and the CI shard index.
- Only a complete execution with the exact assigned batches can pass. Keep process exit/signal failures even when reporting fails. Consolidate normalized results under stable native target/suite/case names, preserving retries and skipped outcomes; batch IDs are assignments, not test identities. Submit one authenticated partition report with explicit attempt/revision through `OnceTestReportService`.
- The server suppresses shared test publication for externally grouped native events; they remain diagnostics. Server rollout must precede the CLI. Require the plan's persisted `reporting_version == 1` before publishing a matrix or artifact: legacy reporting duplicates rerun facts and cannot honor producer ordering. Account enrollment remains an explicit server-side rollout decision. Batch timing history is not connected to planning, so opaque units currently receive default estimates.
- Contract coverage is in `TuistTestCommandTests/OnceTestReportTests`; the public English guide is `server/priv/docs/en/guides/features/test-sharding/once.md`.
