defmodule Tuist.Repo.Migrations.RemoteIndexCacheEventsProjectIdIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # This index is duplicated. index_cache_events_on_project_id also exists.
    drop index(:cache_events, [:project_id],
           name: :cache_events_project_id_index,
           concurrently: true
         )
  end
end
