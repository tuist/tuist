defmodule Atlas.Repo.Migrations.CreateSocialPostRevisions do
  use Ecto.Migration

  def change do
    create table(:social_post_revisions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :revision_number, :integer, null: false
      add :body, :text, null: false
      add :notes, :text
      add :status, :string, null: false, default: "draft"
      add :created_by_agent, :string

      add :social_channel_idea_id,
          references(:social_channel_ideas, type: :binary_id, on_delete: :delete_all), null: false

      add :author_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create index(:social_post_revisions, [:social_channel_idea_id])
    create index(:social_post_revisions, [:author_id])
    create index(:social_post_revisions, [:status])

    create unique_index(:social_post_revisions, [:social_channel_idea_id, :revision_number],
             name: :social_post_revisions_idea_revision_number_index
           )

    create unique_index(:social_post_revisions, [:social_channel_idea_id],
             where: "status = 'published'",
             name: :social_post_revisions_one_published_per_idea_index
           )
  end
end
