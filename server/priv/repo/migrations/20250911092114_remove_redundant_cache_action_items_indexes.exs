defmodule Tuist.Repo.Migrations.RemoveRedundantCacheActionItemsIndexes do
  use Ecto.Migration

  def up do
    # Remove redundant hash-only index (composite index covers this)
    drop index(:cache_action_items, [:hash])

    # Remove redundant project_id-only index (composite index can handle project_id queries)
    drop index(:cache_action_items, [:project_id])
  end

  def down do
    create index(:cache_action_items, [:hash])
    create index(:cache_action_items, [:project_id])
  end
end
