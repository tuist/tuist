defmodule Atlas.Repo.Migrations.CreateMoodboardResources do
  use Ecto.Migration

  def change do
    create table(:moodboard_resources, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :url, :text, null: false
      add :description, :text
      add :image_url, :text
      add :tags, {:array, :string}, null: false, default: []
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :timestamptz)
    end

    create unique_index(:moodboard_resources, [:url])
    create index(:moodboard_resources, [:created_by_id])
    create index(:moodboard_resources, [:inserted_at, :id])
  end
end
