# Runner cache volume metadata

`../cache_volumes.ex` owns allocation, publication, invalidation and analytics;
these schemas persist volume identities and per-job uses.

- Account-scope all browser reads and writes. Agent reports, uploads and
  publications are separately authenticated and bound to the node that received
  the allocation. Read-only image `retain` and `download` requests may name a use
  from any node: hosts prefetch a macOS custom HEAD (`recent_macos_heads/3`,
  listed by `VolumePrefetch`) under the use that published it.
- Every macOS job keeps its Xcode and module caches on the `tuist-xcode`
  (30 GB by default) and `tuist-module` (20 GB) custom volumes, which take
  requested sizes like any custom volume and which the module-cache and xcode-cache actions, Buildkite plugins and GitLab snippets
  attach. Dispatch stamps only the account label; the cache signing grant
  follows trust. The dashboard
  names the volumes "Xcode cache" and "Module cache". There is no built-in
  per-account cache volume: HEADs, orphans and `runner-volume-masters` objects
  belong to custom volumes only.
- `recent_job_volumes/3` predicts a queued job's custom volumes for dispatch
  affinity and for the macOS Pod placement preferences in the scaling signals:
  the volumes jobs of the same repository, workflow name and job name attached
  since a cutoff, each with the cache disk room a host reserves for it (what it
  is expected to write, as runner-cache's `Identity.ExpectedBytes` computes it
  from the capacity and the saved head's size, or the checkout growth
  reservation; keep the two in step). It starts from the account's
  volumes so the uses `(volume_id, inserted_at)` index applies;
  `VolumeAffinities` caches it per account and repository.
  `allocated_reserved_bytes/2` is the same room for the volumes running jobs
  already allocated, which `VolumeAffinities` subtracts from a host's advertised
  capacity so affinity never prefers a host that cannot fit a job's volumes.
- A report's `mounted_generation` records the older saved generation a host
  mounted when the use's base was not local; only values below the base are kept.
  Such uses may still publish (last publication wins). `older_copy?/1` drives the
  "Older copy" dashboard badge and the API status description.
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
  (425 to the authenticated agent). The Linux and macOS agents wait 25 seconds
  per Pod, shared by its checkout and volumes, and ask once after that;
  unknown/closed sessions and denied provider identities remain unavailable.
  An unbound session also enqueues `ExecutionLookupWorker`, which reads the
  job GitHub's API names the runner on and records it through
  `Dispatch.record_execution/3`, because webhook delivery can lag by minutes.
  The API's job status can still read `queued` for minutes after the job
  started, so a `queued` job carrying the runner's name binds too; the log line
  `recorded execution from GitHub API` says which status bound it.
  An agent that is still answered 425 at its deadline reports `execution_pending`
  (macOS reason, Linux 425 to the guest), never `denied`.
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

- Allocation picks each use's capacity (`runner_cache_volume_uses.volume_bytes`).
  The host sends `requested_volume_bytes` (whole GB, 1 to 100; anything else is no
  request) and `max_volume_bytes` (absent: 32 GB). Each key has a default capacity
  (`default_volume_bytes/1`): 30 GB for `tuist-xcode`, 20 GB for every other key.
  With a saved head the capacity is the larger of the lineage capacity (the head
  use's `volume_bytes`, else the key default) and the request; without one it is
  the request or the key default. A capacity above the host maximum rolls back and
  answers 507 `capacity`. Uses that may publish record their request on the volume
  (`requested_volume_bytes`); a smaller one is the pending size shown until the
  volume next starts empty. Allocations and prefetch listings send `volume_bytes`
  and the head use's measured `head_size_bytes`.
- Allocation clears a custom volume whose saved head measured at 80% or more of
  the capacity chosen for the job (`full?/2`) once a use cloned from that head
  reached 99% of its own (`out_of_space?/2`), under the same row lock and with the
  same generation bump as deletion, then sizes the use as for an empty volume.
  The decision precedes the host-maximum check, so a refused job changes nothing.
  Unknown sizes never clear. The dashboard warns on heads nearly full at the
  capacity the next job gets and on failed jobs whose copy reached 99%.

- Evict cache data after seven days without a mount. Refresh last_used_at only
  on the first valid attachment report for a use, never allocation, heartbeats
  or publication. A five-minute sweep and allocation/report paths invalidate
  expired generations under the volume lock; keep live copies until fenced and
  track physical deletion separately. Reusing an evicted identity starts cold.
- The same sweep retires a copy no host has reported for a day
  (`retire_unreported/1`), except the volume's saved head: it is deleted as an
  acknowledged deletion would delete it, so storage and used space stop counting
  it. A host that still reports a retired copy is told to `delete` it.

- Volume-count history includes unmeasured allocations and counts each volume only once across its concurrent retained copies. Byte history remains unknown until measured. Gauge trends compare the selected period end with its start (the previous period end). Require a recorded baseline at the boundary for a calculated comparison; never substitute the first later measurement for missing history. The UI follows Jobs by rendering unavailable comparisons with the shared zero-trend fallback.

- Detail analytics scope storage and activity to both account and volume. Aggregate uses by attachment time (hourly up to two days, daily otherwise), count each mount once, and calculate hit rate from known outcomes only. Empty buckets have zero uses and unknown hit rate. Detail widgets compare with the previous period like the account widgets: used space through the same boundary-baseline rule, hit rate as a relative change, and job runs as a percentage (absolute "+N" from zero). Recent jobs use a bounded five-row query; the Jobs tab retains pagination.

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
- `retain` returns the HEAD generation and digests so a host can refresh a
  superseded local master. `download` with a `generation` other than the use's
  base serves only the current HEAD, for a use on the same node in the same
  uncleared lineage, even after that use finished. Never widen it to other
  generations, nodes or lineages.
  A refreshed master keeps authorizing through the use that first installed
  it, so do not add use-age checks to `retain` or this `download`; a use pruned
  from history only costs that host one remote restore.
- `linux-<scope>` and `macos-<scope>` are the only valid storage names
  (`VolumeHeads.valid_storage_volume_name?/1`); attachment and publication go
  through the separately authenticated host agent. Export includes image
  digests/generation fields.
- `Schemas` owns the shared OpenAPI/MCP contracts inside the Tuist boundary.
  Keep `CacheVolumes`, `Query` and `Schemas` exported from `Tuist`; MCP must not
  depend on `TuistWeb`. Validate with the Boundary compiler, which dev skips.

- Public byte sums are integers, never Decimal strings. Serialize timestamps at
  whole-second precision for the generated Swift client's default ISO8601 decoder.
  Test measured PostgreSQL rows through JSON schema validation, not only empty fixtures.

- macOS custom volumes reuse the shared runner-cache lifecycle with an APFS
  backend; rollout and compatibility are documented in `infra/tart-kubelet/custom-cache-volumes.md` at repository root.

- Allocation resolves execution binding and platform in one session query. Apply
  the platform rollout flag to that same result, including pending (425) sessions.

- The writer policy is the job's runner profile, resolved from `requested_dispatch_label` (`runs-on`, the Buildkite queue or the GitLab tag), for every provider. A missing profile or a legacy pool label applies a new `%Profile{}`'s policy. On a profile, `cache_writer_all_branches` (default true) lets every job with a writer branch save (plus legacy `writer_default_branch` uses). When false, `cache_writer_default_branch` (default true) lets `trusted` jobs save, and `cache_writer_branches` (NULL when empty, served as []) adds branches: same-repository push/schedule/dispatch runs and verified PR heads match exact names or `*` patterns (`Profile.cache_writer_branch?/2`); push/dispatch head_branch may be a tag. Buildkite writer branches are webhook/schedule builds without a tag whose pull request repository, if any, is the pipeline's (`Buildkite.same_repository?/2`), captured with the identity; GitLab writer branches are push/schedule/web branch pipelines of the project (`Identity.gitlab_writer_branch/1`), plus merge request pipelines (`refs/merge-requests/N/{head,merge,train}`, source `merge_request_event`) whose merge request, read with the connection's optional `api_token`, has the project as both target and source; they write under the source branch. Without a token or on a failed lookup they stay read-only. Forks and pull_request_target never qualify. Lock the profile FOR SHARE before the volume at allocation and record `writer_profile_id`, `writer_branch` and `writer_default_branch`. Profile updates and deletes re-evaluate pending grants against the new policy (deletion falls back to a new profile's policy) and revoke under the volume locks in the profile row's transaction. Commit false always disables publication. Volumes record GitHub's `default_branch`. `runner_cache_volumes.writer_branches` is no longer read.

- There is no per-job save intent. Allocation ignores the `commit` field older agents still send; their explicit modes target the removed `authorize-commit` route and fail as unsupported before allocating. `runner_cache_volume_uses.commit_mode` is no longer read.

- `checkout` is a reserved key: `allocate/1` refuses it, and only
  `allocate_checkout/1` (host agent, `/runners/cache-volumes/checkout`) creates
  it, for GitHub jobs whose runner profile keeps cached checkouts on, on github.com
  installations. No GitHub token is involved: the host builds the master from what
  jobs export after their own checkout. A use never gets `can_publish`, so a job's
  own branch is never sealed or published. Instead the host publishes its master
  under the use through `image/3` (`checkout_publish`): only the generation and the
  use not having published yet are checked, not the job's outcome or the use's
  state, and a published checkout use is released (`delete`) when its job is gone.
  `recent_macos_heads` skips checkout volumes; a host restores their HEAD itself.
  `default_branch_job` is the resolved identity's `trusted` (same repository,
  default branch, push/schedule/dispatch), so a fork's branch named like the
  default branch never qualifies. `may_start_master` is `writer_allowed?/3` for the
  job's profile (a new `%Profile{}` without one): a job with a writer branch that
  profile saves from may start the lineage's first master, so forks and
  pull_request_target never do. `checkout_publish` enforces the same: a use
  without `writer_default_branch` publishes only from `base_generation` 0 and
  only with a `writer_branch`. `volume_key` (sha256 of the volume id) lets
  hosts drop a cleared volume's copies, and a checkout `download` only needs the
  current lineage, so a restore outlives the job that asked for it.
  A job also needs its runner profile's `cached_checkouts` (default true; a job on
  a legacy label has it on); the profile modal shows the toggle on macOS and
  Linux profiles. Linux hosts (the
  runners-controller cache agent, `amd64`) allocate through the same endpoint:
  the volume identity carries the session's platform, architecture and UID, so a
  repository has separate macOS and Linux checkout volumes, published and
  restored through the same `image/3` clauses.
