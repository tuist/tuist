defmodule Tuist.Repo.Migrations.CommandEventsProjectIdCreatedAtIndex do
  use Ecto.Migration

  # As recommended by https://fly.io/phoenix-files/migration-recipes/#adding-an-index
  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index("command_events", [:project_id, :created_at])
  end
end
