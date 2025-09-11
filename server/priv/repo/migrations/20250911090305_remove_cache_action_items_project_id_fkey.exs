defmodule Tuist.Repo.Migrations.RemoveCacheActionItemsProjectIdFkey do
  use Ecto.Migration

  def up do
    drop constraint(:cache_action_items, "cache_action_items_project_id_fkey")
  end

  def down do
    alter table(:cache_action_items) do
      modify :project_id, references(:projects, on_delete: :delete_all)
    end
  end
end
