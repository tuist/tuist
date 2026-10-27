defmodule Tuist.Repo.Migrations.AddRunnerSessionsOpenNodeIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:runner_sessions, [:node_name], where: "ended_at IS NULL", concurrently: true)
  end
end
