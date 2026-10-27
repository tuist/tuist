defmodule Tuist.Repo.Migrations.CreateRunnerClaims do
  use Ecto.Migration

  # Thin claim-lock + cap-counter table for the dispatch path.
  #
  # ClickHouse `runner_jobs` holds the full workflow_job lifecycle
  # (queued → claimed → running → completed) and powers the
  # customer-facing surfaces. But ClickHouse can't give us OLTP
  # primitives — no row locks, no unique constraints across
  # replicas — so this table carries the two bits we genuinely
  # need OLTP for:
  #
  #   1. **Claim atomicity.** The PRIMARY KEY on `workflow_job_id`
  #      means `INSERT … ON CONFLICT DO NOTHING` is atomic by
  #      construction. Two warm Pods racing to claim the same
  #      workflow_job both attempt the INSERT; Postgres serializes,
  #      one row lands, the other gets zero rows back and bails
  #      cleanly. No verify-readback, no eventual-consistency
  #      window.
  #
  #   2. **Per-account cap counting.** `SELECT account_id,
  #      count(*) FROM runner_claims WHERE fleet_name = $1 GROUP
  #      BY account_id` is an indexed lookup against this table
  #      and gives us the current in-flight count without
  #      querying ClickHouse or the K8s apiserver.
  #
  # Protocol:
  #
  #   * On claim: INSERT here (atomic), then INSERT a 'claimed'
  #     state row into ClickHouse `runner_jobs` for customer
  #     visibility.
  #   * On finalize (mint success → 'running'): leave this row;
  #     it still counts toward cap. INSERT 'running' state into
  #     ClickHouse.
  #   * On completion (workflow_job.completed webhook): DELETE
  #     this row; INSERT 'completed' state into ClickHouse.
  #   * On release (mint failure): DELETE this row + INSERT
  #     'queued' state into ClickHouse (re-surface as claimable).
  #   * On stale (server crashed mid-mint, claim older than 5
  #     min): the worker DELETEs the row + INSERTs 'queued' into
  #     ClickHouse.
  #
  # The (workflow_job_id, claimed_at) tuple is the claim handle
  # for the finalize/release race fix — DELETE filters on both so
  # a stale serve's eventual release doesn't stomp a re-claim's
  # row.
  #
  # Steady-state row count is bounded by the number of currently
  # in-flight workflow_jobs across all customers (~hostCount, a
  # few tens). The indexes stay tight.
  def change do
    create table(:runner_claims, primary_key: false) do
      add :workflow_job_id, :bigint, primary_key: true, null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :fleet_name, :string, null: false
      add :pod_name, :string, null: false
      add :claimed_at, :timestamptz, null: false, default: fragment("now()")
    end

    # Cap counting: per-fleet, per-account.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_claims, [:fleet_name, :account_id])

    # Stale-claim reaper scans by `claimed_at`.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_claims, [:claimed_at])
  end
end
