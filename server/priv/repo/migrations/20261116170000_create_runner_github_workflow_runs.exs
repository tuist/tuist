defmodule Tuist.Repo.Migrations.CreateRunnerGithubWorkflowRuns do
  use Ecto.Migration

  def change do
    create table(:runner_github_workflow_runs) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :workflow_run_id, :bigint, null: false
      add :run_attempt, :integer, null: false
      # The run as `Tuist.Runners.WorkflowRuns.from_webhook/1` keeps it.
      add :run, :map, null: false
      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:runner_github_workflow_runs, [
             :account_id,
             :workflow_run_id,
             :run_attempt
           ])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_github_workflow_runs, [:inserted_at])
  end
end
