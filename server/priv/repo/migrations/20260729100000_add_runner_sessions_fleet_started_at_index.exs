defmodule Tuist.Repo.Migrations.AddRunnerSessionsFleetStartedAtIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:runner_sessions, [:fleet_name, :started_at], concurrently: true)
  end
end
