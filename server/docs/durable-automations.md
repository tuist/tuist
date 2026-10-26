# Durable automation execution

The durable path removes action and notification latency from metric evaluation.
It is initially opt-in per alert so mixed-version deployments cannot execute the
same work through both the legacy and durable paths.

The motivating timeout was an evaluation that processed 401 test transitions in
four minutes before Oban stopped it; its retry processed another 33. Evaluation
included sequential state changes, Slack HTTP requests and history writes, so
total duration grew with the number of matching tests. Increasing the timeout
would retain that unbounded work and the crash windows between side effects.
Persisted pages bound evaluation work, while separate transition and delivery
jobs let quarantine complete independently of notification throughput.

## Execution contract

`AlertEvaluationWorker` schedules a persisted evaluation. `EvaluationPageWorker`
reads at most 200 test cases, calculates transitions, and atomically commits the
transition records, their Oban jobs, its cursor and the next page job. Competing
workers may repeat a read but only one can commit a page. Full evaluations use the
existing catalog keyset; rolling evaluations page the inserted-run index with a
fixed upper watermark. The calendar cutoff is pinned, but aggregate measurements
remain live: this does not introduce historical snapshot semantics.

`automation_test_states` records the latest applied trigger/recovery state and
one pending owner. Its sequence increases for every new transition. Existing
active ClickHouse history seeds a state only when it is first encountered. Pending
transitions suppress duplicate scheduling; subsequent recovery or retriggering
uses a new sequence. Explicit baseline action requests and event-driven chains
can queue behind the current owner. Each evaluation page commits before it is
acknowledged. Established rolling alerts also have the periodic scheduler as a
backstop if an ingestion callback is lost.

`TransitionWorker` prepares state-change events durably before writing them to
ClickHouse. Replays preserve event IDs and timestamps, including inputs to the
state materialized view, so replaying an earlier action cannot overwrite a later
manual edit. State filters are checked before preparation. A prepared action has
been authorized and can finish after configuration changes; unstarted work checks
its captured configuration revision before proceeding. A recovery that no longer
matches its state filter still rearms the alert without undoing a manual change.
The revision includes a monotonic configuration counter, so reverting an edit or
disabling and re-enabling an alert cannot resurrect stale work.

The transition checkpoint, Slack delivery records and downstream fan-out job are
one PostgreSQL transaction. Fan-out atomically queues webhooks, MCP events and
subscribed test-event automations, with stable source identities and a depth limit
of 10. A Slack outage does not prevent quarantine or recovery from completing.
LiveView updates read the latest test state after committing fan-out, so delayed
delivery does not replace a newer manual edit in an open page.

`AutomationDeliveryWorker` sends one request per attempt, without Req retries.
Connection/pool waits are limited to five seconds and response waits to ten
seconds. A PostgreSQL session advisory lock and cooldown coordinate each channel
across replicas. HTTP 429 schedules another attempt after `Retry-After`; 5xx and
transport failures retry with capped exponential backoff. Permanent rejections
and exhausted retries remain visible as failed deliveries.
Each lock uses a dedicated connection linked to the worker, with reconnection
disabled. Killing the worker closes the session; losing the session terminates
the worker. Budget one additional PostgreSQL connection per active transition or
delivery worker (up to ten per replica with the default queue limits).

Notifications are **at least once**, not exactly once. A crash after Slack accepts
a message but before the successful response is durably recorded can produce a
duplicate. State mutations and completed transition fan-out have separate durable
checkpoints and do not repeat merely because a notification failed.

## Deployment and activation

1. Apply PostgreSQL migration `20261026170000`. It is additive and leaves every
   existing alert on the legacy path. No new ClickHouse schema is required.
2. Deploy compatible binaries to every worker replica. Confirm the new
   `automation_transitions` and `automation_deliveries` queues are consumed.
   These queues require direct PostgreSQL sessions, as configured for web pods;
   workers reject transaction-mode poolers because they cannot own session locks.
3. Drain any executing legacy evaluation for the selected alert. From an
   authenticated administrative release console call:

   ```elixir
   Tuist.Automations.Execution.enable(alert_id)
   ```

   Activation locks Oban claiming while checking for executing single-alert or
   project-group evaluations, then changes the alert under its row lock. If it
   returns `{:error, :evaluation_in_progress}`, wait for that job to finish and
   retry. Pending jobs re-read the switch when they start. This check cannot make
   an old binary compatible: complete the deployment before activation.
4. Observe one alert before expanding. Verify evaluation progress, transition
   completion and notification throughput using the operations helpers below and
   existing Oban queue metrics. No production alert is activated by a migration.

Do not toggle the flag back or roll back to an old binary while durable work is
pending. Pause scheduling for the alert, drain or explicitly reconcile pending
transitions and deliveries, and verify ClickHouse history has caught up before
returning it to inline execution. Keep the additive tables during rollback.

## Inspection and replay

These functions are administrative entry points; none is exposed through the
public API. They do not return encrypted action payloads or webhook URLs.

```elixir
Tuist.Automations.Execution.Operations.status(alert_id)
Tuist.Automations.Execution.Operations.retry_evaluation(evaluation_id)
Tuist.Automations.Execution.Operations.retry_transition(transition_id)
Tuist.Automations.Execution.Operations.retry_fanout(transition_id)
Tuist.Automations.Execution.Operations.retry_delivery(delivery_id)
```

Status reports counts, oldest timestamps, attempts and recorded errors. Inspect
Oban's errors for exception detail and timeouts. Exhausted page jobs leave their
run and cursor intact; exhausted transitions retain any prepared payload. Replay
inserts a job without clearing those checkpoints. Retrying a permanent Slack
failure requires fixing the destination first; stale notification definitions
are cancelled rather than sent using an obsolete configuration.

Hourly pruning removes up to 500 terminal evaluations and 500 terminal transitions
older than 30 days. A transition is retained if fan-out is unfinished or any
notification is pending/failed. Per-test state persists with the alert; destination
cooldown keys are shared hashes of channel identifiers and contain no credentials.
Deleting an alert cascades evaluations, states, transitions and deliveries.

## Validation

The focused suites are `test/tuist/automations/execution_test.exs` and
`test/tuist/automations/execution/`. Run the existing automation, scheduler,
monitor, Slack client and state-update regressions as well. Failure injection must
include the interval after a successful ClickHouse write and before the PostgreSQL
checkpoint, and concurrency tests must use independent database connections.
