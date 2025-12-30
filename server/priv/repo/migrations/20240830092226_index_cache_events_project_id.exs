defmodule Tuist.Repo.Migrations.IndexCacheEventsProjectId do
  use Ecto.Migration
  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index("cache_events", [:project_id], concurrently: true)
  end
end
