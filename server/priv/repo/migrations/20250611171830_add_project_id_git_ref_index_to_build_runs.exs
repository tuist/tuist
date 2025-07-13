defmodule Tuist.Repo.Migrations.AddProjectIdGitRefIndexToBuildRuns do
  use Ecto.Migration

  def change do
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:build_runs, [:project_id, :git_ref, :inserted_at])
  end
end
