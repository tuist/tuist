# Idempotent Requests (Context)

This context deduplicates report-creation requests that carry a client-supplied id, so a client can retry a request whose response it lost.

## Responsibilities
- `IdempotentRequests.run/5` claims `(project_id, kind, request_id)` in the PostgreSQL `idempotent_requests` table before the creation runs. A completed claim replays the recorded result; a claim in progress is waited on (10 s) and otherwise answered as `{:error, :in_progress}`, which controllers return as 503 with `retry-after`. A failed or raising creation releases its claim; a claim older than its 5-minute lease is taken over (a replica killed mid-request blocks retries for at most that long). Only the lease holder completes or releases a claim.
- Users: `createTest` (`"test_run"`, keyed by the request id, not the merged shard run id), `createCommandEvent` (`"command_event"`) and Gradle `createBuild` (`"gradle_build"`, authenticated requests only). The recorded result is the response body; for test runs it also carries the processing job arguments so a retry after a failed `ProcessXcresultWorker` insert schedules it again (`update_result/4` then marks it scheduled).
- Ids that are missing or not UUIDs skip the claim and behave as before.
- `Workers.PruneWorker` (every five minutes) deletes claims an hour after they were taken, in batches, and prunes expired `Tuist.Authentication.RefreshReplays` entries.
- The worker also prunes expired browser telemetry receipts in batches of 5,000;
  reschedule when either report claims or browser receipts fill a pruning batch.

## Guardrails
- The ClickHouse writes stay outside any PostgreSQL transaction; the claim is the only coordination.
- Results are stored with `:erlang.term_to_binary/2` and read with `binary_to_term(..., [:safe])`: keep them to plain terms.
- Update `server/data-export.md` when the stored result changes.

## Related Context
- Parent: `server/lib/tuist/AGENTS.md`
- Refresh-token replay window: `server/lib/tuist/authentication/AGENTS.md`
