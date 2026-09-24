# Runner cache volume metadata

`../cache_volumes.ex` owns allocation, publication, invalidation and analytics;
these schemas persist volume identities and per-job uses.

- Account-scope all browser reads and writes. Agent reports are separately
  authenticated and bound to the node that received the allocation.
- Increment generation under the volume row lock on deletion.
  Publication takes the same lock, so old clones cannot resurrect cleared data.
- The live executed-job binding and `Identity` provider adapter determine scope
  and trust for GitHub, Buildkite and GitLab. Never authorize from job variables.
  Provider/instance/immutable scope join account/key/platform/architecture/UID in identity.
  PRs can read private clones; publication requires a successful eligible job
  and local fencing. Preserve legacy GitHub volume UUIDs when changing identity.
  See `infra/runners-controller/cache-volume-integrations.md` for provider policies.
- Capture Buildkite's normalized cache identity before returning its acquisition
  token. The Stacks job payload returns 404 once the agent has acquired the job.
  Persist only scope and save permission on the account-owned job mapping, never
  the provider environment, commands or credentials. Failed refresh clears the
  snapshot; missing snapshots and disabled installations decline attachment.
- GitLab's verified job response supplies trigger type in `pipeline.source`.
  Fall back to the top-level `source` only when that nested field is
  absent. Missing, unknown or denied nested sources never grant save permission.
- An open Linux or macOS session awaiting its verified execution binding returns pending
  (425 to the authenticated agent). The agent retries for at most 30 seconds;
  unknown/closed sessions and denied provider identities remain unavailable.
- Logical invalidation and acknowledged physical deletion are distinct states.
- Preserve unknown metrics. Reported logical usage is not unique physical allocation.
- Size measurements are appended on the first report, changed used/capacity
  bytes, and acknowledged deletion, inside the same transaction as the use.
  Identical reports must not duplicate measurements. Preserve historical values
  and nulls. Account totals include pending deletion and expose unmeasured-copy
  counts; never present partial sums as complete storage. Measurement history
  follows usage retention and is not yet a billing ledger.
- Keep `server/data-export.md` current and test lifecycle changes against Postgres.

- Storage history is an account-scoped hourly rollup of per-copy measurement deltas for the selected date range (seven days by default). Seed it with earlier reports, carry unchanged sizes forward, preserve unknown fields, and subtract confirmed deletions. Do not sum repeated reports as new storage or present this series as billable usage.

- Evict cache data after seven days without a mount. Refresh last_used_at only
  on the first valid attachment report for a use, never allocation, heartbeats
  or publication. A five-minute sweep and allocation/report paths invalidate
  expired generations under the volume lock; keep live copies until fenced and
  track physical deletion separately. Reusing an evicted identity starts cold.

- Volume-count history includes unmeasured allocations and counts each volume only once across its concurrent retained copies. Byte history remains unknown until measured. Gauge trends compare the selected period end with its start (the previous period end). Require a recorded baseline at the boundary for a calculated comparison; never substitute the first later measurement for missing history. The UI follows Jobs by rendering unavailable comparisons with the shared zero-trend fallback.

- Detail analytics scope storage and activity to both account and volume. Aggregate uses by attachment time (hourly up to two days, daily otherwise), count each mount once, and calculate hit rate from known outcomes only. Empty buckets have zero uses and unknown hit rate. Recent jobs use a bounded five-row query; the Jobs tab retains pagination.

- Job detail references require account, workflow run and job IDs. Return only attached uses, keeping the latest mount per volume; acknowledged deletion does not remove the historical reference before normal history retention.

- Inventory sorting happens in PostgreSQL before the 20-row page limit, with volume ID as a stable tie-breaker and unknown values last in either direction. Size sorts aggregate retained copies with the same empty/unknown semantics as the displayed values; deleted copies do not contribute.

- Job history left-joins existing job and workflow names by account, run and job identity. Missing or pruned metadata must not hide volume history; keep the job ID as the UI fallback.

- Account usage analytics reuse the volume mount aggregation without a volume filter, retaining account and date scoping. Compute hit rate from total hits divided by known outcomes, not averages of volume or time-bucket rates. Unknown outcomes do not count as misses.

- `Query` is the public HTTP/MCP/CLI read and clear boundary. Reuse lifecycle and
  analytics queries, account-scope every lookup, and serialize an explicit allowlist
  without node, pod, host-image or credential details. HTTP/MCP use runners-read for data
  and account-update for clearing. Limit pages to 100 rows and ranges to 90 days;
  never coerce unknown byte counts or hit outcomes to zero.

- Public inventory filters use exact name (key) and repository equality, combined
  with AND before counting and paginating. The dashboard retains its free-text search.

- Custom image publication reuses `VolumeHeads` and `Runners`' immutable master
  URLs, checksum signing, compare-and-swap and delayed object reclamation.
  `base_generation` is the shared HEAD version; `generation` is the independent
  custom-volume clear/expiry epoch. Lock the custom volume through publication
  and clearing so a cleared lineage cannot be resurrected. Publication is
  idempotent by usage ID and both digests. A sealed report alone never publishes.
- `linux-<scope>` and `macos-<scope>` names are valid for custom storage only.
  Keep macOS dispatch validation restricted to built-in repository/account caches;
  custom attachment uses the separate authenticated host agent. Export includes
  image digests/generation fields.
- `Schemas` owns the shared OpenAPI/MCP contracts inside the Tuist boundary.
  Keep `CacheVolumes`, `Query` and `Schemas` exported from `Tuist`; MCP must not
  depend on `TuistWeb`. Validate with the Boundary compiler, which dev skips.

- Public byte sums are integers, never Decimal strings. Serialize timestamps at
  whole-second precision for the generated Swift client's default ISO8601 decoder.
  Test measured PostgreSQL rows through JSON schema validation, not only empty fixtures.

- macOS custom volumes retain automatic built-in Tuist/CAS caches. They reuse the
  shared runner-cache lifecycle with an APFS backend; rollout and compatibility
  are documented in `infra/tart-kubelet/custom-cache-volumes.md` at repository root.
