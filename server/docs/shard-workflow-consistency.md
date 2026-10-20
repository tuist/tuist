# Immutable shard reporting

## Contract

Newly enrolled plans store their complete assignments and reporting version in one immutable ClickHouse row. The plan UUID is also the merged test-run UUID. Shards append independent observations; no application process claims a run ID or reads, merges and overwrites a shared summary.

`latest_shard_test_reports` selects each shard by the producer order `(shard_attempt, report_phase, shard_report_revision, report_digest)`. The phases are initial processing, failed processing, and a parsed terminal result, in that order. Attempts take precedence over phases, and phases over revisions. Missing attempt/revision values default to zero. Producers must increase the attempt for a new execution and the revision for a corrected terminal report. Conflicting payloads with the same logical version have a deterministic digest tie-break, not a promise that the last HTTP request wins. Old clients cannot express ordered terminal corrections within one plan. Some integrations include a workflow attempt in the plan reference; validate each producer rather than inferring report ordering from a CI identifier.

`reported_test_run_summaries` folds those latest observations; `test_run_summaries` combines that fold with legacy runs. Point lookups keep the projection-friendly physical legacy query and only fall back to the immutable fold, whose source has an ID projection; they do not force every legacy lookup through `FINAL`. Failure takes precedence; success requires a terminal result from every expected shard. One-shard plans preserve processing and skipped outcomes. An incomplete run with no report received for six hours derives failure at query time. A late successful report repairs that result without a reaper rewrite. This timeout is not a retention or retry deadline and does not emit a transactional timeout event.

Once the same immutable observations become visible, readers converge regardless of delivery order, duplicates or application replica. A stale replica can temporarily return incomplete or stale results, but cannot persist an incomplete aggregate that prevents later repair. Immediate globally fresh reads are **not** promised by this change.

## Fact ingestion and retries

`Tuist.Ingestion.Batch` stages core facts in the calling process and flushes directly to the configured ingestion writer before inserting the report. Each schema holds at most 8 MiB of encoded rows plus one oversized row. Existing shared buffers remain unchanged outside this path. Request-local staging is a transport optimization, not distributed authority or durable acceptance.

Facts have deterministic IDs scoped to the plan, shard, attempt, revision, phase and semantic payload. Receipt time and the caller's random run UUID are not producer versions; conflicting logical versions fall back to the full report digest. A report carries its fact-set UUID; `reported_test_*` views select the matching module, suite, case, run-error, destination and stress-candidate rows. Run-scoped case lists and metrics use those views for immutable runs, so an old attempt arriving later cannot contaminate the selected execution. Existing project/test-case history and its materialized analytics remain execution history, not an authoritative workflow-state machine. Historical fact IDs remain readable directly. Terminal corrections must include their complete execution payload, not merely a replacement status.

A core write failure prevents publication of the report. A crash between fact writes and report publication can leave orphaned facts; current-run views exclude them, and a client/job retry can publish the report. Replays can still insert physical duplicates. Child-row views group identical payloads and retain the earliest insertion timestamp; occurrence-scoped IDs preserve genuinely repeated failures/arguments/repetitions. Replacement/deduplicating reads, rather than finite ClickHouse insertion-token windows, establish the new run-level contract. Original case-sensitive upload UUIDs remain in `source_test_run_id` on each raw observation and travel through processor jobs so xcresult/stress bundles can be located after job pruning. The existing download action keeps the canonical run URL and serves the first available current shard bundle in shard-index order; it does not synthesize a merged xcresult. Existing case-history materialized aggregates are not made exactly once by deterministic fact IDs.

Acknowledgement confirms the configured writer's accepted inserts, subject to its engine and replication settings. It does not prove visibility on every replica or durable delivery through the detached migration mirror. There is no cross-store completion transaction, PostgreSQL workflow snapshot, projection worker or projection repair cursor.

## Events, enrichment and availability

The HTTP ingest response has the canonical ID and a conservative local status; a multi-shard success response remains `in_progress`. Read APIs derive the aggregate. Completion publication requires ClickHouse, not both ClickHouse and PostgreSQL workflow coordination. Existing project/account authorization, artifact-processing jobs and other operational features still use PostgreSQL.

`test_run.failed` remains an observation-driven, best-effort notification, not an exactly-once transition outbox. A reported failure can be delivered even if a later correction succeeds; a crash after report publication can lose notification delivery. Decisions requiring authoritative fresh state or durable transition delivery must use a separately specified transactional boundary, not a potentially stale aggregate. This change does not add one implicitly.

Coverage publication, test controls, flakiness-history enrichment, automation lifecycle and migration-mirror deletion ordering remain separate mechanisms. This work does not make their read/modify/write operations transactional or their materialized aggregates duplicate-free.

## Compatibility rollout

1. Apply the additive ClickHouse migration to every ingestion/read deployment, including the migration mirror, before compatible binaries query the new views. Migration DDL is not mirrored. `SchemaClone.reconcile/1` must add missing columns on existing tables before creating missing tables/views, because the new views reference `reporting_version` and `shard_report_id`. Verify the dependent views can be queried on the actual read route after the first reconciliation; the best-effort reconciliation log alone is not a deployment gate.
2. Benchmark legacy aggregate readers before deploying compatible binaries: their summary views are queried even while the creation flag is off. `test_run_summaries` reads legacy `test_runs FINAL`, so previously undeduplicated lists and analytics can change counts and durations with enrollment disabled. Deploy all web, build and xcresult processor binaries with the account-scoped `:immutable_shard_reports` creation flag **off**. Check the release baked into every Tart image too. All readers must support the persisted reporting version before enrollment.
3. Establish the deployment's required plan read-after-write contract. Plans are read from the ingestion route, not the detached mirror, but routing alone does not ensure fresh reads across native replicas. Validate engine-appropriate quorum/sequential-read settings or define retryable plan-not-visible behavior. This implementation does not configure quorum or make the mirror synchronous.
4. **Ship and deploy producer ordering support before enabling any account.** Every producer that can reuse a plan must send a monotonically increasing `shard_attempt` for a new execution and an increased `shard_report_revision` for a corrected terminal payload within that execution. Today's CLI does not send these fields, and `CIInfo.shardReference` excludes the CI attempt, so CI re-runs can reuse the same plan. A CLI change mapping `GITHUB_RUN_ATTEMPT` (and provider-specific equivalents) to the report attempt is an enrollment prerequisite, not part of this server change. Zero defaults preserve wire compatibility but cannot order a failed execution and its passing re-run: the digest tie-break can retain the failure. Validate every enrolled producer's retry/correction behavior; do not enable an account still using incompatible producers.
5. Canary only approved accounts/producers after those prerequisites are met. Observe synchronous fact flush latency, query read rows/memory, report growth, partial-visibility windows and ClickHouse errors. Benchmark current-fact joins with representative project history before enrollment, including their effect on legacy projects once the report table is populated.
6. Disabling the flag stops creation of new version-1 plans. Existing version-1 plans retain their contract; legacy plans retain the legacy merge path. Do not roll consumers back to pre-compatibility binaries after enrollment. Historical legacy runs are not silently adopted.

No production flags, deployments or existing plans are changed here. Legacy retirement and any change to immediate freshness or business-event delivery require a separate rollout decision.

## Validation

- Real ClickHouse tests exercise immutable assignment reads, canonical IDs, duplicate-insensitive run/shard counts, sparse metadata, producer attempts/revisions, late processing reports, parsed-result recovery, fact publication ordering and failed writes.
- Independent ClickHouse connections race simultaneous first/final reports and duplicate replays. Separate tests use deliberately reversed receipt clocks and derive timeout recovery without a stored merged row. These are single-server concurrency tests, **not** replicated-cluster partition, quorum or failover tests.
- Current-run detail tests require a newer successful attempt to hide older failed execution facts even when the failure arrives last; unpublished facts must remain outside current-run views.
- Schema reconciliation tests use scratch ClickHouse source/destination databases to verify columns are added before dependent views, the first pass produces queryable views on an existing destination, empty destinations still clone, and a second pass is idempotent. They do not validate replicated-database DDL propagation.
- Legacy shard, controller, ingestion, analytics and xcresult tests guard compatibility. Migration rollback/forward and representative query plans must be checked alongside formatting and API regeneration.

## Separate consistency work

- Transactional test controls and automation activation/recovery, with durable events where required.
- Log-archive completeness, coverage and Git-listing manifests/reconciliation.
- Cross-replica migration deletion intent and destination tombstones.
- Replicated ClickHouse freshness/failure tests and operational durability settings.
