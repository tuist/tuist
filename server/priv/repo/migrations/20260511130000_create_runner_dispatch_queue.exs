defmodule Tuist.Repo.Migrations.CreateRunnerDispatchQueue do
  use Ecto.Migration

  # Burst queue. Each row is a pending workflow_job the webhook
  # handler accepted but a warm Pod hasn't claimed yet — either
  # because the fleet is saturated, or because the customer is at
  # `accounts.runner_max_concurrent` and the entry is waiting its
  # turn.
  #
  # A polling warm Pod's dispatch call:
  #   1. takes a snapshot of K8s Pod counts per account-owner label,
  #   2. inside one Postgres tx, picks the oldest row whose account
  #      isn't already at cap, acquires a per-account advisory lock,
  #      re-checks in-flight (claimed-but-not-finalised) queue rows
  #      for that account, and UPDATEs `claimed_at = now()`,
  #   3. mints a JIT and stamps the Pod label,
  #   4. on success, DELETEs the row; on mint failure, NULLs
  #      `claimed_at` so the row goes back to the pool.
  #
  # `claimed_at` is the soft-claim marker. A stale-claim reaper
  # (`Tuist.Runners.StaleClaimsWorker`) clears claims older than a
  # threshold so a server crash mid-mint doesn't strand the row.
  def change do
    create table(:runner_dispatch_queue) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :fleet_name, :string, null: false
      add :repo, :string, null: false
      add :claimed_at, :timestamptz, null: true

      timestamps(type: :timestamptz, updated_at: false)
    end

    # Oldest-eligible lookup per fleet — narrowed to pending rows
    # via partial index so the claim query never scans soft-claimed
    # rows that have already been UPDATEd with `claimed_at`.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_dispatch_queue, [:fleet_name, :inserted_at],
             where: "claimed_at IS NULL",
             name: :runner_dispatch_queue_pending_idx
           )

    # Account cascade-delete lookup + in-flight count per account
    # for the cap re-check inside `claim_oldest_eligible`.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_dispatch_queue, [:account_id])

    # Stale-claim reaper scans by `claimed_at`. The partial filter
    # keeps this index tiny — only soft-claimed rows are indexed.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_dispatch_queue, [:claimed_at],
             where: "claimed_at IS NOT NULL",
             name: :runner_dispatch_queue_claimed_idx
           )
  end
end
