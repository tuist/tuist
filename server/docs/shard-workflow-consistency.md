# Shard workflow consistency

## Contract

A successfully created PostgreSQL-owned plan is readable, with all assignments, from any application replica. Its canonical merged-run identity is allocated once with the plan. Completed reports are merged under a PostgreSQL row lock, never by reading back an asynchronous ClickHouse copy. A delayed report writer cannot supersede a later merged snapshot: publication timestamps advance using the database clock and the previous version, not the application node's clock.

`shard_workflows` owns plan metadata, the canonical test-run UUID and the merged metadata snapshot. `shard_workflow_shards` stores immutable assignments and one latest status per shard index under a composite primary key. Both cascade with project deletion and have no time-based expiry. Historical execution facts and charts remain in ClickHouse.

Core report facts are ingested and their local buffers successfully flushed before the completion transaction. A failed flush fails the report, leaving completion unchanged so the client/job can retry. This is not an atomic transaction spanning ClickHouse and PostgreSQL: a crash before the PostgreSQL commit can leave replayed facts. Existing ingestion/read deduplication still applies. Flushes and projection acknowledgements confirm the configured ingestion writer, not visibility or durable delivery through the detached migration mirror. Mirror reconciliation remains a separate migration concern. Coverage publication remains a separate, best-effort enrichment and is not fixed by this change.

The control transaction enqueues an Oban projection job. Jobs read current authoritative state and can be delivered more than once. A monotonic `projected_version` cursor is acknowledged only after publication succeeds. The hourly stale-run worker also re-enqueues up to 500 unacknowledged workflows, using a partial pending-projection index, so discarded or pruned jobs remain recoverable without another client report. Repair attempts rotate by a separate timestamp rather than report activity, preventing permanently rejected rows from monopolizing the batch or postponing stale-report expiry. Plans are immutable and plan metrics deduplicate their IDs; shard metrics collapse by shard/report version; merged test rows use their strictly increasing snapshot timestamp as the replacement version. Destination deduplication tokens only reduce duplicate work within the destination's finite deduplication window. Module/suite assignments are not copied to ClickHouse for these plans; detail reads attach them from PostgreSQL.

The API has no ordered client attempt/revision field. Terminal results may be corrected by later terminal reports, matching the existing last-arriving-report contract. A retried initial `processing` report cannot roll a terminal shard back to processing. Exactly-once report ingestion or chronological ordering of independently retried terminal reports is not claimed. A late parsed report can also correct a stale-run timeout from failure to success; an already-published failure notification is not revoked, matching the legacy behavior.

## Compatibility rollout

1. Apply the additive PostgreSQL migration and reconciled processor grants.
2. Deploy this compatibility release with `:postgres_shard_plans` **off**. All readers understand persisted PostgreSQL ownership; plan creation remains legacy by default.
3. Verify every web and build/xcresult processor runtime is at least this release. In particular, verify the release baked into every xcresult Tart image, not just the web Deployment. Do not enable creation while any older consumer remains.
4. Enable the account-scoped `:postgres_shard_plans` flag for an approved canary account. Observe report latency and buffer flushes, PostgreSQL row-lock/pool pressure, Oban projection retries and ClickHouse query errors before expanding.
5. Disable the creation flag to stop enrollment of new references if necessary. Existing PostgreSQL plans always retain their authority. Subsequent plans reusing an enrolled project/reference also stay PostgreSQL-owned, preventing a stale creation-flag cache from sending a later plan for that reference back to the legacy store. Do not roll binaries back to a pre-compatibility release after enrollment.

No production flags, deployments or existing plans are changed by this implementation. Existing legacy plans keep the old coordination behavior; they are not silently adopted from a potentially incomplete ClickHouse mirror. Removing that path requires a separately planned migration/retirement, including support for historical bundle downloads and delayed client retries. The six-hour stale-run threshold is not a plan retention or client-retry guarantee.

## Validation scenarios

- Create module and suite plans with routed ClickHouse reads returning no rows; fetch by ID and reference on a different process, including catch-all assignments.
- Race first and final shard reports through independent PostgreSQL connections. Require one canonical run, a complete successful status, preserved metadata and monotonically ordered projection versions.
- Park an outbox job, commit another report and replay both jobs. Require eventual latest state without rolling status or duration back. Discard/prune a pending job and run reconciliation; require re-enqueue and a cursor acknowledgement only after successful publication. A late older acknowledgement must not clear a newer pending version.
- Fail a core buffer flush: no terminal shard state or merged snapshot may be committed.
- Present the stale-run reaper with an old `in_progress` analytics row for an authoritatively completed workflow. It must not mark it failed.
- Expire a genuinely abandoned workflow through PostgreSQL, and verify that failed shard states and the projection job commit together.
- Verify processor-role access to the new tables, project isolation/cascades and duplicate-insensitive shard metrics.

## Follow-up work outside this slice

1. Move test quarantine/current control state and automation trigger/recovery lifecycle into PostgreSQL with atomic transitions and transactional event publication. A stale state read must not suppress an enable/unmute operation.
2. Build fetched GitHub log archives while streaming their original bytes. For other report paths, persist expected content and finalize only after completeness is verified.
3. Give Git file listings and coverage reports durable upload/revision manifests and completeness checks. Serialize coverage folds only after their expected inputs are visible; reconcile missing inputs rather than trusting fixed sleeps or readiness thresholds.
4. Persist migration deletion intent and reconcile destination tombstones. A local shadow-task drain cannot order writes on other application replicas.
5. Audit each `select_sequential_consistency` call against the actual ClickHouse engine. SharedMergeTree and ReplicatedMergeTree do not provide interchangeable guarantees; a setting or writer pinning cannot replace transactional workflow ownership.
