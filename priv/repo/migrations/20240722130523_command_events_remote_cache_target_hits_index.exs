defmodule Tuist.Repo.Migrations.CommandEventsRemoteCacheTargetHitsIndex do
  use Ecto.Migration

  # As recommended by https://fly.io/phoenix-files/migration-recipes/#adding-an-index
  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index("command_events", [:remote_cache_target_hits])
  end
end
