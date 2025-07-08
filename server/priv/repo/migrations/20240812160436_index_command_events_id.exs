defmodule Tuist.Repo.Migrations.IndexCommandEventsId do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:command_events, [:id])
  end
end
