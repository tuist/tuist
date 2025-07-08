defmodule Tuist.Repo.Migrations.IndexCacheEventsProjectIdEventType do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index("cache_events", [:project_id, :event_type], concurrently: true)
  end
end
