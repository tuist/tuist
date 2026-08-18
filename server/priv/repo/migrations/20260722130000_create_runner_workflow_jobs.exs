defmodule Tuist.Repo.Migrations.CreateRunnerWorkflowJobs do
  use Ecto.Migration

  def change do
    create table(:runner_workflow_jobs, primary_key: false) do
      add :workflow_job_id, :bigint, primary_key: true, null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :fleet_name, :string, null: false
      add :status, :string, null: false
      add :conclusion, :string
      add :platform, :string, null: false, default: ""
      add :vcpus, :integer, null: false, default: 0
      add :memory_gb, :integer, null: false, default: 0
      add :repository, :string, null: false, default: ""
      add :workflow_run_id, :bigint, null: false, default: 0
      add :workflow_name, :string, null: false, default: ""
      add :run_attempt, :integer, null: false, default: 1
      add :job_name, :string, null: false, default: ""
      add :head_branch, :string, null: false, default: ""
      add :head_sha, :string, null: false, default: ""
      add :requested_dispatch_label, :string, null: false, default: ""
      add :enqueued_at, :timestamptz, null: false
      add :claimed_at, :timestamptz
      add :started_at, :timestamptz
      add :completed_at, :timestamptz
      add :pod_name, :string
      add :runner_name, :string
      add :executed_workflow_job_id, :bigint

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_workflow_jobs, [:fleet_name, :status, :enqueued_at])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_workflow_jobs, [:account_id])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_workflow_jobs, [:updated_at])

    # The recovery sweeps scan one live status across every fleet, and
    # rows are kept for the account's lifetime, so without a partial
    # index each sweep would walk the full history. The live set is a
    # tiny fraction of the table.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_workflow_jobs, [:started_at],
             where: "status = 'running'",
             name: :runner_workflow_jobs_running_started_at_index
           )

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_workflow_jobs, [:enqueued_at],
             where: "status = 'queued'",
             name: :runner_workflow_jobs_queued_enqueued_at_index
           )

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_workflow_jobs, [:status, :workflow_job_id],
             where: "status IN ('queued', 'claimed', 'running')",
             name: :runner_workflow_jobs_live_index
           )
  end
end
