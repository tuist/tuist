# Automations

Metric alerts have two execution paths during rollout. `Alert.durable_execution`
selects the PostgreSQL-backed pipeline in `Execution`; existing alerts default to
legacy inline execution. Do not expose that switch through ordinary alert edits.

- Evaluation pages contain at most 200 test cases. Reserve transitions, insert
  Oban jobs and advance the page cursor in one PostgreSQL transaction. Cursor
  comparison prevents duplicate commits from competing page workers. Calendar
  cutoff dates are pinned to the evaluation time; measurements are live aggregates,
  not historical snapshots. Rolling windows retain the existing bounded lookback.
- PostgreSQL state is authoritative after an alert/test/generation has been seen.
  Import existing active ClickHouse history on first encounter, without replaying
  its actions. Keep the event generation distinct from baseline attempt generation.
- A state row owns one executing transition; sequence numbers order event chains
  and explicit baseline reapplications. Session advisory locks serialize execution
  across replicas using dedicated linked connections with reconnection disabled;
  never use reusable Repo connections for session locks. Short row-lock transactions authorize and checkpoint writes;
  never hold a row lock over Slack HTTP.
- Persist state-event payloads before writing ClickHouse. Retries retain IDs and
  timestamps, including materialized-view inputs, so they cannot override later
  manual edits. A prepared action may finish after an alert edit. Unstarted actions
  and notifications recheck the current definition and enabled flag.
- Transition completion atomically persists Slack deliveries and fan-out jobs.
  Fan-out must enqueue webhooks, MCP events and subscribed automation work in the
  checkpoint transaction; do not use best-effort helpers that swallow failures.
  Preserve source-event deduplication and the depth-10 chain bound across jobs.
- Slack delivery uses one bounded HTTP attempt per job, with shared destination
  locking/cooldown and `Retry-After` snoozes. External delivery is at least once:
  acceptance followed by a crash before acknowledgment can duplicate a message.
- Retain unresolved work for inspection/replay. Hourly retention removes only
  terminal evaluations and fully delivered/cancelled transitions older than 30
  days, in batches of 500. Compact per-test state and destination cooldown keys
  persist; alert deletion cascades its execution records.
- Test real PostgreSQL contention using independent connections, not shared
  sandbox transactions. Cover cursor rollback, ClickHouse-write replay, manual
  edits, generations, baselines, rearming, fan-out, and Slack failures.
