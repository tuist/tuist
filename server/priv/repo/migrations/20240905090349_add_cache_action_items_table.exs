defmodule Tuist.Repo.Migrations.AddCacheActionItemsTable do
  use Ecto.Migration

  def change do
    create table(:cache_action_items, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :hash, :string, null: false
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      timestamps(type: :timestamptz)
    end

    create unique_index(:cache_action_items, [:hash, :project_id])
    create index(:cache_action_items, [:project_id])
  end
end
