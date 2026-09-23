# Offline assignment experiment

This pure policy is retained only for the offline scheduling comparison. The
production shadow collector, HTTP client, observer and server endpoint have been
removed. Do not wire this package into the controller manager or add cluster,
database, credential or network access.

- Version 2 uses account/platform dominant resource share, with an oldest-first
  override after two minutes. Each virtual assignment charges the shared budget.
- Exact pool, platform and shape must match. Claims override stale queued jobs
  and busy Pods, including provider executed-job remapping.
- macOS cache affinity recognizes account-scoped repository volume hashes and
  the account-wide `tuist-cache` fallback. Residency only chooses among available
  runners; it never delays demand or grants cache access.
- Inputs retain the former bounded snapshot format for repeatable experiments.
  Advance the version when changing policy semantics and update the comparison
  report. Historical `pull_shadow_policy` / `push_shadow_policy` output names
  identify this experiment, not active production components.

See [simulation boundary](../AGENTS.md) and
[results and limitations](../../../scheduling-simulation.md).
Run `go test ./internal/simulation/...` from the controller directory.
