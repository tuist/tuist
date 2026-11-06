# Application-managed telemetry retention and bounded manifests

Status: implemented experimentally by PR #32, now extended to traces. The sections below preserve the original design proposal; `docs/retention.md` and `docs/architecture.md` describe actual behavior and limits. Expanded after the user's metadata-growth objection and joint review with Claude, October 9, 2026. Bounded active manifests and reclaimable deletion metadata are part of this feature, not deferred production prerequisites.

## Goal and scope

Configure logs/metrics retention in Pulse, with metadata cost proportional to the retained window and unfinished cleanup rather than process lifetime. Object storage remains the sole shared authority. Acknowledgement requires durable segments, required metadata pages, and the tenant/signal root-manifest CAS. No database, WAL, leader election, extra mutable publication authority, or infrastructure-remediation MCP tools.

V1 is event-time retention, not cache eviction or a compliance-erasure SLA. Logs and metrics are implemented; traces are not. Make the machinery signal-generic so traces can join later, without exposing a trace-retention setting prematurely. Alerting/audit namespaces, tiering, per-tenant policy overrides, and splitting boundary-spanning Parquet segments remain out of scope.

[Architecture](../docs/architecture.md) remains authoritative. This is a plan, not an implemented format. Update its flat-manifest and "forever" descriptions, runtime/Helm configuration, self-monitoring, and recovery docs alongside implementation.

## Why the earlier plan was incomplete

The previous draft kept a flat manifest and permanent tombstones, then declared bounded metadata a separate prerequisite. That makes retention a feature that eventually rejects ingest because its own metadata fills up. It is not a sustainable retention design.

At one publication/second/signal, 30 days contains 2.59 million active entries; moving them into permanent tombstones only changes their classification. The replacement design must solve both:

1. Active entries are paged; no request reads/rewrites the entire retained segment set.
2. Retirement fences and superseded metadata pages are reclaimed once their whole time bucket expires, using the irreversible retention floor instead of permanent per-key tombstones.

Capacity remains bounded by a supported workload and healthy maintenance throughput. No design promises bounded storage under unlimited ingest, paused retention, permanent provider failures, or arbitrarily delayed external writes. Resource limits remain safety valves, not a normal uptime-dependent stop.

## Current integration points

- `S3.append_unbuffered/5` PUTs a segment before `ManifestOwner` registration. `AppendBuffer` coalesces concurrent unkeyed requests locally; keyed/overflow requests remain direct. Coalescing is disabled by default, so one-second publications are a modeling assumption, not a current guarantee.
- Manifest formats 1/2 are flat; version-2 compaction tombstones are permanent. `Manifest.merge/2` fences retired-key retries.
- Metrics compaction exists; log compaction does not. Cleanup must be signal-generic and independent of merge enablement.
- Tenant discovery and eligible-worker rendezvous ownership exist. Reuse these primitives; conditional object writes remain the correctness fence.
- Queries serve stale manifests after transport/decode refresh errors. Missing metric objects restart once; missing log objects are currently silently skipped. Both need explicit retention-safe behavior.
- Legacy bootstrap can publish a LIST reconstruction, including query-first and CAS-conflict paths. That is forbidden after managed paging/retention activation.

## Storage design: bounded root, hot tail, and immutable time-bucket pages

### One authoritative root

Keep `tenants/<tenant>/v4/signal=<signal>/manifest.json` as the **only conditional publication authority**. Use manifest **format 3**, which has not shipped; `/v4/` remains the existing segment-key layout and is not a manifest format number.

The bounded root contains:

- effective retention duration, maximum supported duration, future skew allowance, fixed bucket width, and monotonic `floor_ns`;
- a fresh publication nonce on every mutating CAS, preventing a stale ETag from becoming valid again through byte-identical root contents;
- a bounded inline hot tail of recent segment/retirement entries;
- bounded bucket descriptors: time range, unique bucket generation, current immutable index reference/digest, aggregate actual time bounds/counts/bytes, state and teardown deadline/cursors;
- bounded maintenance cursors, a monotonic `reclaimed_through_ns` sweep watermark, bounded floor-aging checkpoints, and aggregate counters, not a lifetime deletion journal.

Initial byte/count budgets for measurement: root 512 KiB and 2,048 descriptors; inline tail 64 KiB and 256 entries. Apply both byte and count ceilings, using actual encoded sizes. Validate defaults against representative summary-heavy entries; limits are not capacity promises.

### Fixed event-time buckets

Assign each segment to exactly one bucket by the `max_ts` encoded in its canonical key. Its records may start much earlier: **query pruning uses aggregate real `min_ts`/`max_ts`, not bucket start time alone**. Unknown summaries always remain scan-eligible.

Choose fixed bucket width at activation from the approved maximum duration, future skew, cleanup grace/backlog allowance, descriptor budget, and measured per-bucket metadata rate. Validate both sides: `(D_max + skew + grace + backlog allowance) / width` fits the descriptor budget, including expiring buckets, and `approved_publication_rate * width` plus compaction-source fences fits actual leaf/index byte and count budgets. Refuse an unsupported duration/rate pair instead of assuming wider buckets solve capacity. A one-hour width can cover 30 days with 720 live time slots plus headroom under the proposed 2,048-descriptor ceiling. Do not choose an hour with a 512-descriptor cap and then promise 30-day retention. Longer windows require an approved coarser width or a separately migrated layout; changing bucket width in place is unsupported.

All accepted record timestamps satisfy the committed floor and a configured maximum future skew (initial candidate: ten minutes, verified with collectors). This prevents arbitrary future timestamps from creating unbounded bucket diversity. Reject the whole invalid request with an explicit permanent client error. No additional lateness cap is needed for metadata lifetime: the floor already bounds admissible old event times. A batch spanning the whole window can keep an old row physically present longer than its logical window; document this distinction.

### Immutable pages

Pages live under a distinct metadata prefix:

`tenants/<tenant>/v4/signal=<signal>/index/<bucket-start>/<bucket-generation>/<attempt-nonce>-<kind>-<digest>.json`

- Active/retirement leaves are sorted by canonical `(max_ts, key)`, at most 256 entries and 64 KiB.
- A bounded bucket index references leaves and carries pruning summaries/occupancy. Initial index ceiling: 512 KiB and 1,024 leaf references.
- Candidate keys include unique attempt nonces and verified digests. References validate key scope, object size, digest, format, ordering and counts before use.
- Pages are immutable. Only the root CAS makes a new index/leaf set visible. Page PUT alone never acknowledges data or changes query-visible state.
- No per-bucket mutable head, independent leaf CAS, or reconstruction from pages. Missing reachable pages fail closed.

The hot tail keeps common appends at segment PUT + root CAS. Create a bucket descriptor with its fresh generation in the **same CAS as its first inline entry**, even if it has no index yet. Tail-only buckets must have durable expiration/grace state; absence of an index is not absence of a bucket. When the tail spills, PUT bounded leaves and a new index for each affected bucket before CAS. The root CAS atomically replaces the affected references and removes exactly the spilled tail entries. Conflict retries rebase on the current root, including its floor, bucket states, and keyed fences. Never reattach pages unreachable from the current base merely because their content looks reusable.

Late/spread-out writes may touch several buckets and need more page PUTs; quantify that separately from the single-hot-bucket case. Admit inline-tail entries only for the current open bucket and buckets within future skew. Valid older entries take bounded copy-on-write paths. Cap affected buckets per root CAS attempt (initially four), with caller-associated continuation or retryable capacity errors for overflow; each conflict retry retains page/work/deadline limits. Seal means spilled/immutable pages, not a blanket rejection of valid late data: an unexpired older bucket can accept bounded mutations. An **expiring** bucket is permanently closed to mutation.

## Metadata reclamation is required in v1

### Bucket-scoped lifetime, not a global GC queue

All committed and unpublished metadata candidates belong to an event-time bucket namespace. Keep superseded page versions only until that bucket expires; they do not enter a permanent root-level garbage map. Bucket teardown can enumerate its immutable prefix with bounded paginated LIST, so deletion of GC-control pages does not produce another GC tree or recursively growing garbage ledger.

Track committed mutation/page-byte counts per bucket, and cap metadata amplification. A hot bucket has a fixed event-time lifetime, not a lifetime across the service. Compaction and valid late mutations must fit this budget. If a bucket's mutation budget is exhausted, stop additional compaction and reject only writes that cannot safely fit that bucket with an explicit capacity error; do not delete active data or let older work starve new buckets.

Candidates from losing/abandoned attempts stay in their bucket prefix until teardown/sweep. Do not immediately delete a candidate just because the newest root lacks its reference: an ambiguous publication may have succeeded and then been superseded, while an older reader still needs it. Prefix teardown after irreversible expiration and grace handles both never-published candidates and previously published versions without that proof burden. A repeated sweep handles candidate PUTs arriving after an earlier sweep. No unreferenced-page adoption is allowed.

### Reclaim retirement fences

Compaction-source retirements remain in bounded bucket pages while those keys might legitimately retry. Floor-rejected uploads do not create per-key retirement entries or recreate dead buckets: they can never pass registration, and a separate bounded sweep reclaims them once their maximum-timestamp bucket is wholly expired and past grace. Each new retirement has a fresh random **generation**; retries within it increment revision. Cleanup completion compares bucket generation, retirement generation and revision. Recreating a forgotten retirement can never reset to an identity a stale cleaner could match.

When `bucket.end_ns <= floor_ns`, every canonical key in it has `max_ts < floor_ns`. Its original records can never pass the whole-request registration floor check again. Therefore, after the reader grace and bucket teardown, drop **all** its per-key fences, leaf references, counters, and bucket descriptor together. The floor, managed-prefix marker, old-version exclusion, and pure registration fence replace those tombstones. Never recreate an expired bucket to record a rejected retry.

This is tombstone GC, not a deferral. It deliberately avoids per-key pruning inside still-live buckets in the first implementation: the maximum extra fence lifetime is a bucket width, and no ABA-prone retired-key resurrection is permitted.

For fully expired re-uploads arriving after their descriptor was removed, bounded cyclic floor-gated object sweeps handle bytes without adding permanent per-key state to the root. Compare the canonical key's maximum timestamp, not a segment path's date partition: segment partitions are derived from `min_ts` and can differ from its metadata bucket.

## Retention, reads, and publication

The retained interval is `[floor_ns, +infinity)`, with equality accepted. With duration D, advancement proposes `max(previous_floor, now_ns - D)`. Keep record nanoseconds and deletion-deadline milliseconds separate. Require synchronized clocks; test overflow and forward/backward jumps. No promise protects against destructive configuration with a badly fast clock.

### Writes and compaction

- Any expired record makes a new request fail before PUT when possible. Missing/zero/negative times are not rewritten to arrival time. Future-skew errors are distinct from retention expiry.
- The **pure root registration transition** checks the latest floor, bucket state, keyed identity and capacity on every CAS attempt. All writers use it, not only `ManifestOwner`.
- Validate buffered callers separately before combining. If a concurrent floor advance invalidates an already-uploaded combined segment, all its callers fail together; do not split/re-upload after ambiguity.
- Independent `ManifestOwner` registrations retain caller-to-entry associations so selective expiry/capacity does not falsely acknowledge unrelated callers.
- Compaction reads bounded source leaves; for the simplest v1 every source must have `min_ts >= floor_ns` and belong to the **same max-timestamp bucket**, with source selection and root publication both enforcing this. The current min-timestamp-hour grouping alone is insufficient; it can select sources from different metadata buckets. Retaining that hour grouping as a secondary constraint is allowed. PUT replacement/pages first; atomically remove sources and publish replacement/retirements through the same root CAS. Validate sources still active and floor unchanged enough for eligibility on retry.
- Retired-key re-uploads remain fenced. An expired replay can fail permanently after an earlier lost success response; never fabricate a fresh durability acknowledgement.

Loki and remote-write retention/future-skew failures return explicit HTTP 400; OTLP JSON uses its corresponding whole-request error envelope. No silent row filtering or retention partial-success path. Capacity/storage uncertainty is a retryable server failure. Count decoded rejected deliveries and verify actual collector retries/drops.

### Queries

Conditional GET the root; inspect inline entries and actual bucket time summaries; fetch only candidate bucket indexes/leaves. Cache immutable pages by digest. Do not hydrate the entire manifest graph. Metadata page fetches/bytes/work have explicit budgets alongside, not hidden outside, segment scan budgets. Time/label summaries that cannot prove completeness do not prune.

Apply the root snapshot's floor in storage decoding, including boundary-spanning rows and missing-object retries. PromQL offsets are resolved before floor clamping; preserve requested evaluation times, lookbacks and expression semantics over empty samples. Raw tools and label discovery use the same contract.

When cache freshness expires, fail closed on transport/decode/budget errors if retention is configured or a managed marker/floor is known. This includes pre-activation cached old-format roots. Managed 404 is an error, not stale success. Alert evaluation requires authoritative freshness; expired history follows configured no-data behavior, whereas refresh failure is not successful no-data. Alert `for` duration is not itself a historical query window.

A missing reachable page or segment restarts the whole scan once from a fresh root under remaining budgets. A second miss errors; **change logs from silent omission to the metrics-style retry**. An expiring bucket is not read by new snapshots; older readers have grace plus retry behavior, not a lease pinning storage indefinitely.

## Bounded expiration and restart-safe teardown

1. Discover tenant prefixes durably; rendezvous selects live retention/cleanup-eligible workers by store identity. Cleanup does not depend on metrics merge enablement.
2. Load the bounded root; validate format, policy, budget and deadline. Inspection previews without writes.
3. Advance floor in one CAS and mark eligible buckets `expiring`, with bucket generation, grace deadline, `stage: data`, and durable cursors. This state is irreversible. Include inline entries in the bucket's frozen reachable set; spill them first or leave them protected in the descriptor until data cleanup completes.
4. Root transitions reject any append/compaction mutation to expiring buckets. Writers racing teardown lose/rebase their CAS; uploaded losers never become visible. The logical floor hides old rows immediately; physical deletion waits for grace.
5. After grace, recheck ownership and clean the **data stage** using only authoritative frozen active/retirement leaves and inline entries; delete their segment keys in bounded batches. Re-delete every retired key regardless of a previous `deleted?` flag, because a late retry may have physically re-uploaded it. Treat confirmed absence as success, rotate failures fairly, and persist cursor/completion through root CAS. Never delete an active key in another bucket/current root. An orphan sweep is not part of this stage: segment paths are partitioned by minimum timestamp and cannot be enumerated from the maximum-timestamp bucket's metadata prefix.
6. Only after indexed data cleanup completes, CAS to `stage: metadata` with enough state to resume **without reading the index/leaf pages being deleted**. No subsequent operation depends on those pages. Bounded paginated LIST deletes the bucket's metadata-generation prefix, including superseded indexes/leaves and abandoned attempts.
7. Persist page-prefix sweep cursor; confirmed absence is success. Once complete, CAS-remove the descriptor and any inline references. Grace-protected old snapshots restart if they miss deleted metadata. Completion matches the exact bucket generation/stage.
8. A **separate tenant/signal floor-gated sweeper**, with bounded durable root cursors, revisits expired segment partitions and metadata bucket prefixes, including removed descriptors and orphan candidate generations. Missing descriptors alone are not proof that reader grace or teardown completed. Maintain a monotonic `reclaimed_through_ns`, advanced only up to the lesser of a grace-aged committed floor and the start of the oldest bucket not fully torn down (if any). Every bucket containing inline or paged entries has a descriptor. Delete only canonical keys with `max_ts < reclaimed_through_ns`, and metadata prefixes whose entire encoded bucket ends at or before that watermark; match root scope and generations, not path dates alone. No current bucket/reader can still require these ranges. This is logically safe even with late PUTs; finite-time physical completeness requires a bounded upload/retry horizon and is not a compliance promise.

Age floors with constant-sized durable checkpoints, not one history entry per CAS: retain a matured floor plus one pending sampled floor and its eligibility deadline. Once the pending floor has aged by G, advance the matured floor and sample the current floor into a new pending checkpoint. This may conservatively delay orphan sweeping by up to an additional grace interval, but does not grow with G or uptime. The reclaimed watermark never moves backward. Include that delay in sweep horizon and cleanup-lag measurements; indexed bucket teardown still follows its own committed grace deadline.

Do not sweep all historical prefixes every minute: that would replace manifest lifetime growth with lifetime-growing LIST cost. Normal sweeps cover a configured sliding horizon H, with H covering the approved timestamp span (`D_max`), skew, bucket width, grace, cleanup lag and supported late-upload/outage allowance. Walk eligible partitions in `[floor_ns - H, floor_ns)` and expired metadata buckets in a similarly bounded range. Cycle to catch PUTs arriving after a previous pass. Perform a resumable one-time historical sweep at migration, and an explicit catch-up after pauses/outages beyond H. Uploads completing outside H are surfaced as an unguaranteed cleanup tail until an operator-requested catch-up; never pretend normal sweeps cover arbitrary late writes.

Never require all cleanup in one CAS/task or materialize LIST results. The object-store NIF needs a bounded paginated listing interface with validated continuation cursors; today's list-all helper is insufficient. Failed keys cannot starve the cursor forever; revisit incomplete ranges fairly instead of requiring one permanently failing key before all other buckets progress. Root/cursor state is bounded, with a supported backlog capacity. Permanent deletion failures remain visible and eventually trigger capacity admission, not silent removal of work.

Initial operation budgets: 1,024 inspected retirement/data entries, 512 deletes/pass, 30-second deadline, bounded CAS attempts, and four in-flight deletes **node-wide across maintenance roles**. Use round-robin tenant/signal/bucket scheduling. Native calls retain admission/supervision until actual completion; timeout or pause is not cancellation.

512 deletes/minute is only a theoretical 8.53/s per owner before processing time and contention. Node capacity is also bounded by roughly `4 / DELETE latency_seconds`. Measure headroom over segment cleanup, compaction sources, metadata versions, and sweeps, using publication/retirement counters rather than event-time estimates. Tune from provider tests; batch DELETE is optional, not assumed by today's NIF.

## What is bounded, and what is not

With finite retention, bounded publication/mutation rates, future skew S, bucket width W, grace G, and healthy cleanup lag C:

- root memory/rewrite bytes: fixed configured byte/count budget;
- query/maintenance memory: selected page/work budgets, not all retained records;
- active metadata and compaction/replay fences: proportional to publications/mutations within roughly `D + S + W + G + C + maintenance_interval`, not total uptime;
- superseded and losing page candidates: bucket-scoped lifetime and measured amplification, reclaimed by teardown/sweeps;
- a segment's residence **after publication** is at most roughly `D + S + W + G + C + maintenance_interval` when its timestamps satisfy admission; an oldest row's age since its event can approach `2D` for a window-spanning batch. Logical visibility still ends at the floor;
- normal sweep listing cost is proportional to configured horizon H, not all elapsed history; expired uploads outside H require explicit catch-up;
- no such physical bound during paused advancement, unlimited retention, sustained cleanup under-capacity, permanent storage errors, or unbounded late PUT completion. Apply capacity admission and surface lag; never forget unfinished work to pretend the bound holds.

The acceptance criterion is a stable plateau over several windows at the target workload, not a pilot that deliberately stops when lifetime publications reach 100,000. Existing global entry-count stops are replaced with per-root/per-page/per-bucket and supported-workload limits.

## Configuration, activation, migration, and recovery

Proposed settings: logs/metrics retention days (`0` stops advancement); mode `observe`/`enforce`/`paused`; maintenance interval (initial 60 seconds); reader/delete grace (initial one hour); maximum future skew. `observe` previews advancement but continues already committed cleanup, `enforce` advances/cleans, `paused` admits neither. Explicit dry-run inspection/policy apply never writes. A pause cannot cancel native work already admitted. Query/ingest enforcement of a committed floor continues in all modes.

Root-recorded duration is authoritative. Workers with a mismatched desired duration refuse advancement. Change it through a bounded resumable release-callable conditional operation with expected old policy, preview and explicit confirmation; production is a Mix release, not a Mix-task environment. Compatible rolling config changes are CAS-fenced. Increasing the window cannot restore expired data and cannot exceed the approved root layout's maximum duration without migration.

Convert only prefixes explicitly activating **finite** retention; do not silently convert every existing prefix on upgrade. Prefixes with retention never enabled stay on the legacy flat format with its existing scalability limitations, rather than acquiring a new fixed descriptor-horizon stop. For already-managed prefixes, `0`, `observe`, or `paused` are temporary non-advancing states, not unlimited-retention steady states: descriptors continue accumulating until advancement/cleanup resumes. Expose remaining descriptor headroom and estimated time-to-capacity with alerts, and document restart/catch-up procedures. Increasing the maximum retention/layout requires explicit migration, not a silent unlimited mode.

Use a permanent zero-byte `.managed` marker before paged conversion/activation. All bootstrap/query-first/CAS-retry/create paths check it immediately before any root `put_if_none_match`, including cached unpublished rebuilt states. Managed missing roots/pages fail closed. No page/segment LIST reconstruction. External mutation/deletion of roots and markers is unsupported; the check/create across objects is not atomic and recovery is required for external deletion races.

Convert flat manifests once, in bounded staging operations: read/validate the legacy snapshot, build immutable bucket pages, then CAS-publish a format-3 root against its original ETag. Conflict rebase/restart preserves concurrent data. Conversion itself needs streaming/bounded legacy parsing or an offline path for manifests above current decode limits; do not assume the entire legacy tree fits memory. Staged pages are not visible until the root CAS. No half-migrated publication. A standalone offline conversion can pause writes, but normal format-3 operation keeps one authority.

Release A fully implements format-3 read/write paging, dedup/floor fences, cache/error behavior and metadata validation, with no activation path. Deploy it everywhere as the rollback target. Release B adds migration, retention and teardown. After conversion, rollback below A is unsupported. Compatible A/B overlap is allowed. Default observe-mode cleanup can resume previously committed compaction cleanup; start paused if that is unwanted. Helm termination grace exceeds operation deadline plus drain margin.

Back up/version the root and required reachable pages coherently. Restoring a root without its immutable pages is not recovery; restoring an old floor/expired generation is unsafe. Root versioning/soft deletion/backups have their own bounded retention and bills; do not promise live-data retention erases backups. Old version roots cannot pin pages forever. Define a finite recovery horizon; either maintain coherent copies in a separately retained backup namespace, or make live page-deletion grace at least that horizon and include it in G above. Root-only versioning is not a coherent backup. Validate backup/page-version reclamation and its extra horizon in the storage/billing plateau tests.

## Request-cost impact

For a single hot bucket, normal append stays at segment PUT + root CAS. A full tail spill adds roughly a leaf and index PUT amortized over the actual byte/count tail capacity (up to 256 entries), not each record. Multiple affected buckets, large summaries, keyed lookups, compaction and migration cost more.

At a three-node, two-signal model with six publications/second, baseline remains 31.1 million segment/root PUTs/month (~$156 at $5/million). With 256-entry single-bucket spills, roughly 121,500 extra leaf/index PUTs add ~$0.61; with 32-entry tails that is roughly $4.86. These are illustrations, not measured guarantees. COW compaction/page versions, root byte traffic, cache misses, teardown GET/LIST/DELETE, orphan sweeps and coherent backups must be included in revised soak/billing estimates. Tigris DELETE is free but its latency consumes cleanup capacity. Do not reuse the old ballpark as production capacity validation.

## Implementation sequence and acceptance tests

1. **Bounded metadata foundation:** format-3 root, time buckets, hot-tail spill, immutable page codec/validation/cache, paginated listing, migration strategy. Property-test encoded byte/count bounds and query completeness for wide time-span segments.
2. **Unified publication/read fences:** pure root transitions for append/compaction, independent caller outcomes, buffered semantics, keyed lookup, future/expired timestamp mappings, query floor/offset/cache handling and log missing-object parity.
3. **Required metadata GC:** descriptors for tail-only buckets, bucket and fresh retirement generations/revisions, irreversible expiration, data-before-pages stages/cursors, descriptor/fence removal, constant-size grace-aging checkpoints and reclaimed-range watermark, repeated expired-prefix sweeps. No permanent tombstone or lifetime garbage map.
4. **Operations:** policy/configuration/mode surface, fair node-wide admission, monitoring, release A/B procedures, coherent backup horizon and activation/recovery docs.
5. **Multi-window provider/load validation:** target normal/late/keyed/high-summary workloads; verify plateau of active and retired metadata, superseded pages, pending buckets, and billed storage over several short test windows. Measure cleanup headroom, root/page rewrite bytes, cache/query costs, collector behavior and backup/version retention. Full supported production-window validation follows before cutover, not automatic activation.

Race tests use injected clocks and deterministic store barriers, not sleeps: tail spill vs append, late writes vs expiring buckets, compaction vs floor/teardown, mixed caller outcomes, ETag ABA, stale retirement completions after generations change, lost root/page PUT/DELETE replies, metadata-stage crash after index deletion, dangling page recovery, unknown/wide timestamp summaries, ownership movement, mode/policy change, cold restart, permanently failing keys, capacity admission and late PUT sweeps. Assert no active-key deletion, no forgotten pending work, no resurrected expired bucket, preservation of eligible acknowledged writes, and remaining scan/deadline budgets on retry.

Implementation checks: focused storage/manifest/maintenance/receiver/query tests; compile with warnings as errors, full tests/precommit, strict Credo, Helm lint/render, and configured Tigris integration. This document-only task does not claim implementation or provider validation.

## Joint review decisions

Earlier reviews established pure floor fencing, missing-log behavior, safe activation, caller associations, lost-response handling and explicit modes. The user correctly rejected leaving bounded metadata as a separate prerequisite.

Claude then recommended time-bucketed immutable pages plus an inline hot tail instead of a general copy-on-write B+tree. This keeps common publication close to two PUTs, bounds root rewriting, scopes metadata garbage to expiring buckets, and lets a monotonic floor replace permanent tombstones. We adopted that direction and included metadata reclamation in the implementation, not as follow-up work. Bucket widths/capacities must actually cover the desired duration; query pruning must use actual segment bounds; teardown must remain restartable after its own index pages are deleted. Claude's follow-up accepted the refinements after three fixes, now incorporated: compaction sources must share the same max-timestamp bucket; orphan sweeps are separate and horizon-bounded rather than a teardown stage or a lifetime full scan; each root CAS caps affected buckets. We also removed the unnecessary garbage ledger (prefix teardown covers all versions), removed permanent bookkeeping for rejected uploads, and made the grace/mutation/rate budgets explicit. The final document review confirmed that active-retention metadata now tracks the window instead of uptime. Incorporated its remaining fixes: convert only explicitly finite-retention prefixes; expose paused/disabled time-to-capacity; create descriptors even for tail-only buckets; require a positively proved, monotonic reclaimed-range watermark for sweeps, aged through constant-sized checkpoints rather than an unbounded floor history. These are design-review conclusions, not an implementation or provider-capacity claim.
