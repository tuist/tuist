defmodule Tuist.Repo.Migrations.AddRunnerWorkflowJobsLogArchivedAt do
  use Ecto.Migration

  def change do
    # Nullable with no default, so PostgreSQL records it in table metadata
    # without rewriting existing rows.
    alter table(:runner_workflow_jobs) do
      add :log_archived_at, :timestamptz
    end
  end
end
