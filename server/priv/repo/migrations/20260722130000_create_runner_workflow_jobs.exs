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
  end
end
