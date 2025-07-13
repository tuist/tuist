defmodule Tuist.Repo.Migrations.IndexCommandEventsBuildRunId do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:command_events, [:build_run_id])
  end
end
