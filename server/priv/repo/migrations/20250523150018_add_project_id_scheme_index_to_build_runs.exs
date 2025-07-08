defmodule Tuist.Repo.Migrations.AddProjectIdSchemeIndexToBuildRuns do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # Hypertables don't support creating indexes concurrently
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:build_runs, [:project_id, :scheme])
  end
end
