defmodule Tuist.IngestRepo.Migrations.CreateRunnerJobs do
  use Ecto.Migration

  # `runner_jobs` is the lifecycle record for every workflow_job we
  # accept for dispatch. One logical row per `workflow_job_id`,
  # walking the state machine
  #
  #     queued → claimed → running → completed
  #
  # State transitions are INSERTs; ReplacingMergeTree merges on
  # `(workflow_job_id)` keeping the row with the latest
  # `updated_at`. The same table backs three customer-facing views:
  #
  #   * "What's queued right now?"   — `WHERE status = 'queued'`
  #   * "What's running right now?"  — `WHERE status IN ('claimed', 'running')`
  #   * "Recent runs"                — `WHERE status = 'completed' ORDER BY completed_at DESC`
  #
  # Cap counting uses the same projection:
  # `count() … WHERE account_id = ? AND status IN ('claimed','running')`.
  #
  # ## Claim semantics on RMT
  #
  # The hot dispatch path can't use `FOR UPDATE SKIP LOCKED` —
  # ClickHouse has no row locks. Instead we use a
  # claim-by-insert-then-verify pattern:
  #
  #   1. Server picks a queued workflow_job (eventual-consistent
  #      read).
  #   2. Server INSERTs a new row with `status='claimed'`,
  #      `pod_name=<our SA name>`, `updated_at=now64(6)`.
  #   3. Server reads back the row via `FINAL` (or `argMax`)
  #      ordered by `(updated_at DESC, pod_name ASC)` for a
  #      deterministic tiebreaker.
  #   4. If the read-back's `pod_name` matches ours, we won the
  #      claim — proceed with JIT mint + state transition to
  #      `running`. Otherwise we lost; abort with no side effects.
  #
  # The tiebreaker means two simultaneous claims compute the SAME
  # winner from any vantage point, so the loser silently bails
  # before any JIT is minted or runner registered. Worst case is
  # 1 extra ClickHouse query per claim; no double-dispatch.
  #
  # ## Idempotency
  #
  # GitHub retries webhooks. A duplicate `workflow_job.queued`
  # INSERTs another row with the same `workflow_job_id` — RMT
  # merges to the latest `updated_at`. Since the duplicate carries
  # the same lifecycle state (still `queued`), the merge is a
  # no-op visible to clients.
  #
  # ## Recovery
  #
  # `StaleClaimsWorker` finds rows stuck in `status='claimed'`
  # past the threshold and INSERTs a fresh row with
  # `status='queued'`, advancing `updated_at`. RMT merge then
  # rolls the row back to claimable. Same shape as the OLTP
  # `release_stale_claims` we used to have, expressed as a state
  # transition instead of a column UPDATE.
  def up do
    create table(:runner_jobs,
             primary_key: false,
             engine: "ReplacingMergeTree(updated_at)",
             options: "PARTITION BY toYYYYMM(enqueued_at) ORDER BY (workflow_job_id)"
           ) do
      # Identity. `workflow_job_id` is GitHub's id — unique
      # per-org and stable across webhook retries; it's our
      # natural primary key.
      add :workflow_job_id, :Int64, null: false

      # Owning account on the Tuist side. Joined back to
      # Postgres `accounts` for the cap config + display.
      add :account_id, :Int64, null: false

      # Routing target. Matches a RunnerPool CR's name; carried
      # in the SA label on the polling Pod.
      add :fleet_name, :"LowCardinality(String)", null: false
      add :repo, :string, null: false

      # GitHub correlation fields — surfaceable on the customer
      # UI so a queued/running entry links back to the GitHub run.
      add :workflow_run_id, :Int64, null: false, default: 0
      add :run_attempt, :Int32, null: false, default: 1
      add :job_name, :string, null: false, default: ""
      add :head_branch, :string, null: false, default: ""
      add :head_sha, :string, null: false, default: ""

      # Lifecycle state. `LowCardinality(String)` lets us
      # introduce a new state (e.g. `cancelled`, `failed`) without
      # a schema migration — ClickHouse builds the dictionary
      # on-the-fly. Enum8 would have been tighter on storage but
      # cost a migration on every new state.
      add :status, :"LowCardinality(String)", null: false

      # Final status when `status = 'completed'`. Empty until then.
      add :conclusion, :"LowCardinality(String)", null: false, default: ""

      # Lifecycle timestamps. `enqueued_at` is set on the first
      # INSERT and carried forward on subsequent state transitions.
      # The later timestamps are set as their corresponding state
      # is entered; we use `0` as the sentinel rather than
      # `Nullable(DateTime64)` because RMT merge requires the
      # version column to be non-Null, and consistent typing
      # simplifies the carry-forward INSERTs.
      add :enqueued_at, :"DateTime64(6, 'UTC')",
        null: false,
        default: fragment("now64(6)")

      add :claimed_at, :"DateTime64(6, 'UTC')", null: false, default: fragment("toDateTime64(0, 6)")
      add :started_at, :"DateTime64(6, 'UTC')", null: false, default: fragment("toDateTime64(0, 6)")
      add :completed_at, :"DateTime64(6, 'UTC')",
        null: false,
        default: fragment("toDateTime64(0, 6)")

      # Binding established at claim/finalize time.
      add :pod_name, :string, null: false, default: ""
      add :runner_name, :string, null: false, default: ""

      # RMT merge picks the row with the latest `updated_at` for
      # each `workflow_job_id`. Every state-transition INSERT
      # advances this timestamp.
      add :updated_at, :"DateTime64(6, 'UTC')",
        null: false,
        default: fragment("now64(6)")
    end

    # Partial-projection-like indexes for the cap-count and
    # customer-facing queries. ClickHouse uses these as skip
    # indexes inside the parts; cheap to maintain on inserts.
    execute(
      "ALTER TABLE runner_jobs ADD INDEX idx_status (status) TYPE set(4) GRANULARITY 4"
    )

    execute(
      "ALTER TABLE runner_jobs ADD INDEX idx_account (account_id) TYPE bloom_filter GRANULARITY 4"
    )
  end

  def down do
    drop table(:runner_jobs)
  end
end
