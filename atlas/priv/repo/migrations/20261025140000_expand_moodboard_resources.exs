defmodule Atlas.Repo.Migrations.ExpandMoodboardResources do
  use Ecto.Migration

  def change do
    alter table(:moodboard_resources) do
      modify :url, :text, null: true, from: {:text, null: false}
      add :content, :text
      add :kind, :string, null: false, default: "link"
      add :source_title, :text
      add :source_description, :text
      add :source_text, :text
      add :preview_image_url, :text
      add :preview_video_url, :text
      add :preview_status, :string, null: false, default: "pending"
      add :preview_revision, :uuid
      add :preview_fetched_at, :timestamptz
    end

    create table(:moodboard_comments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :resource_id,
          references(:moodboard_resources, type: :binary_id, on_delete: :delete_all), null: false

      add :author_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :body, :text, null: false
      timestamps(type: :timestamptz)
    end

    create index(:moodboard_comments, [:resource_id, :inserted_at, :id])
    create index(:moodboard_comments, [:author_id])
  end
end
