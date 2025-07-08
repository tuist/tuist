defmodule Tuist.Repo.Migrations.IndexCacheEventsHashEventTypeCreatedAt do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:cache_events, [:hash, :event_type, :created_at])
  end
end
