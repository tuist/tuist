defmodule Atlas.Repo.Migrations.CreateBlogPostIdeaComments do
  use Ecto.Migration

  def change do
    create table(:blog_post_idea_comments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :blog_post_idea_id,
          references(:blog_post_ideas, type: :binary_id, on_delete: :delete_all),
          null: false

      add :author_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :body, :text, null: false

      timestamps()
    end

    create index(:blog_post_idea_comments, [:blog_post_idea_id, :inserted_at])
    create index(:blog_post_idea_comments, [:author_id])
  end
end
