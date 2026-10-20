defmodule Atlas.Repo.Migrations.AddSlackThreadToBlogPostIdeas do
  use Ecto.Migration

  def change do
    # Slack message timestamps are globally unique, so the thread ts alone is
    # enough to match an inbound #marketing reply back to the idea it belongs to.
    alter table(:blog_post_ideas) do
      add :slack_thread_ts, :string
    end

    create index(:blog_post_ideas, [:slack_thread_ts])

    alter table(:blog_post_idea_comments) do
      add :author_name, :string
    end
  end
end
