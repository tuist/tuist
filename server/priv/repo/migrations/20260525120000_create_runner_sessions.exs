defmodule Tuist.Repo.Migrations.CreateRunnerSessions do
  use Ecto.Migration

  # Append-only billing record: one row per runner Pod we
  # provisioned, keyed off the Pod's wall-clock lifetime (the
  # signal Namespace and Blacksmith bill against) rather than the
  # workflow_job's GitHub-reported runtime. `runner_claims` is
  # deleted on completion so it can't drive historical invoicing;
  # `runner_jobs` (CH) tracks the GitHub-side workflow_job
  # lifecycle which doesn't match what we charge for.
  #
  # Retries via `Jobs.record_queued/1` create a new row per
  # re-claim — no unique constraint on `workflow_job_id` — so the
  # customer is billed for every Pod they actually held.
  def change do
    create table(:runner_sessions) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :workflow_job_id, :bigint, null: false
      add :fleet_name, :string, null: false
      add :pod_name, :string, null: false, default: ""
      add :runner_name, :string, null: false, default: ""
      # Denormalised from the workflow_job so the Compute Minutes
      # widget's repository / workflow_name filters don't have to
      # join against ClickHouse.
      add :repository, :string, null: false, default: ""
      add :workflow_name, :string, null: false, default: ""

      # `ended_at` stays NULL until completion; the Billing module
      # clamps open sessions so an orphaned Pod doesn't bill
      # forever.
      add :started_at, :timestamptz, null: false
      add :ended_at, :timestamptz

      timestamps(type: :timestamptz)
    end

    # Billing-period scan: sessions for account X overlapping
    # [start, end].
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_sessions, [:account_id, :started_at])

    # Close-by-workflow_job lookup from `Jobs.complete/2`. Not
    # unique — retries produce duplicate workflow_job_ids.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_sessions, [:workflow_job_id])
  end
end
