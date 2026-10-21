# Once test-report publication and recovery

## State and compatibility

After durably persisting run/case staging, the event stream normally commits a separate PostgreSQL publication intent with an Oban job. It does not wait for ClickHouse report publication. If intent creation itself fails, the staged source survives and the bounded terminal-run sweep can reconstruct the intent; outages exceeding that sweep window require an explicit backfill. `PublishTestReportWorker` consumes the dedicated `once_test_reports` queue, which only releases containing this worker poll. Older replicas cannot consume these jobs.

`once_runs.test_report_published_at` remains a **legacy admission reservation**, not proof of completion. The unchanged old writer conditionally sets that column before writing. The new writer reserves it in the same transaction as its publication intent and job, so exactly one protocol wins that reservation. For new intents, only `once_test_report_publications.state = 'published'` proves that all captured chunks were acknowledged. Completion refreshes the legacy timestamp as well.

An older writer that reserved a run first retains its previous semantics. This change does not infer that its report completed or repair historical partial publications. Rolling back to binaries without this worker delays new intents until roll-forward; do not clear their reservations. The age-independent publication sweep resumes preparation/pending work after roll-forward. A separate two-hour terminal-run sweep repairs a missed intent, not arbitrary historical legacy claims. Application rollback must retain the new table; do not roll back its schema while intents/snapshots remain pending or uncertain.

## Publication

The worker captures the existing shared report builder's buffer submissions in its own process, preserving the ordinary path for other ingestion. It persists an immutable compressed snapshot of row IDs, timestamps, field values, deferred webhook effects, single-partition chunks and their precomputed content tokens. Preparation failures leave the durable intent and staged source intact. The 64 MiB compressed snapshot limit is not a bound on total builder memory.

Each chunk is marked in flight in PostgreSQL **before** sending it. An acknowledged write advances a durable checkpoint. Retries resume acknowledged prefixes without resending them. The parent report is written last. Publication completion and its follow-up job commit together. Deferred webhook enqueueing and its completion checkpoint are one PostgreSQL transaction; downstream webhook delivery and optional notifications are not exactly once.

The five-minute job timeout is shorter than the six-minute claim lease. A killed job between chunks can resume; a killed job with an in-flight chunk cannot safely assume whether ClickHouse accepted it. A write error, lost response, or expired in-flight owner moves the publication to `uncertain`. Only the driver's explicit pre-send pool checkout timeout clears the in-flight marker for an automatic retry; errors after sending are never classified by a transport message string. Automatic recovery does **not** resend that chunk. Even a short retry horizon cannot guarantee ClickHouse deduplication: its retention is count- as well as time-bounded. Tokens are defense in depth, not the correctness fence. The writer disables both the repo's generic transport retries and DBConnection checkout resends, and forces synchronous server inserts. No fleet-wide ClickHouse deduplication-window changes are required.

## Detect and reconcile uncertain writes

Alert on increases in `tuist_once_events_test_report_publication_total{outcome="uncertain"}` or `outcome="preparation_failed"`, and inspect retained publication rows and failed Oban jobs. Metrics have no run/account/project labels. Missing metrics are not evidence that no publication is stuck. Preparation failures and uncertain writes are logged without report payloads.

Reconciliation is an explicit maintenance operation requiring the normal production authorization. Nothing in the worker performs it automatically:

1. Identify the publication's exact `id`, `owner`, `in_flight_chunk`, `next_chunk`, and immutable payload. Decode the snapshot in the matching server release with `:erlang.binary_to_term(payload, [:safe])`. Schema-removing upgrades must drain or migrate pending snapshots first.
2. Prove that the old worker **and every outstanding ClickHouse query for it** have stopped. A lease expiry, a pod's phase, or an empty read is not that proof. Do not resume while a late insert can still commit.
3. Inspect the exact uncertain chunk on every relevant storage replica using the read-only repo or approved operational tooling. Verify identities **and payloads**, not a parent report or an aggregate count alone. Account for replication lag and pending writes.
4. If all rows match, call `Tuist.OnceEvents.TestReportIngestor.reconcile_chunk(id, owner, index, :present)`. If every row is conclusively absent after quiescence, use `:absent`. The function checks the exact uncertain owner and checkpoint and transactionally requeues work. A stale decision is rejected.
5. Partial, mismatched, inaccessible or otherwise unknown results must remain `uncertain`. Escalate for a separately reviewed repair; do not reset the legacy reservation, rebuild children with fresh IDs, or blindly replay the chunk.
6. Verify the retained publication reaches `published`, the expected children and parent are readable, and follow-ups have progressed. Keep an audit record of the quiescence and storage evidence used.

These steps are a safe repair interface, not an automatic exactly-once cross-database transaction or a claim that power loss, storage failure and arbitrary schema changes cannot lose data.
