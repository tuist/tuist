# Automation evaluation and notifications

- Established metric evaluations enqueue candidate test IDs in batches of at most 200. Batches re-read current conditions and history before executing transitions. Keep baseline handling on its existing checkpoint path.
- Persist every batch before advancing a scoped evaluation watermark. Failed action/enqueue results must make the batch retry; completed transitions are skipped using the existing ClickHouse ledger.
- Batch uniqueness coalesces waiting/retryable jobs, but excludes executing jobs so an ingestion update can schedule a successor after a worker has read its inputs. This is not cross-replica exactly-once execution.
- Slack actions persist rendered messages in Oban; only `SlackNotificationWorker` performs HTTP. Keep webhook URLs encrypted and resolve legacy bot credentials at delivery time. Skip deleted/disabled alerts and removed action definitions.
- Slack uses one bounded HTTP attempt per job. Return `{:snooze, seconds}` for `Retry-After`, errors for transient failures, and discard for permanent failures. Delivery is at least once: acceptance followed by a crash can duplicate a message. Oban owns retries, inspection, and pruning; there is no separate delivery ledger or activation flag.
