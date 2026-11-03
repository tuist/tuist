defmodule Tuist.Repo.Migrations.AddRunnerWorkflowJobsExecutorClaimedAt do
  use Ecto.Migration

  def change do
    # Nullable with no default, so PostgreSQL records it in table metadata
    # without rewriting existing rows.
    alter table(:runner_workflow_jobs) do
      add :executor_claimed_at, :timestamptz
    end
  end
end
