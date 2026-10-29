defmodule Atlas.Repo.Migrations.CreateSocialChannelIdeas do
  use Ecto.Migration

  def change do
    create table(:social_channel_ideas, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :title, :string, null: false
      add :description, :text
      add :status, :string, null: false, default: "idea"
      add :created_by_agent, :string

      add :author_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create index(:social_channel_ideas, [:status])
    create index(:social_channel_ideas, [:author_id])
    create index(:social_channel_ideas, [:inserted_at])
  end
end
