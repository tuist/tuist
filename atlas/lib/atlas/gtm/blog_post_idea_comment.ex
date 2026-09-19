defmodule Atlas.GTM.BlogPostIdeaComment do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.GTM.BlogPostIdea
  alias Atlas.Users.User

  schema "blog_post_idea_comments" do
    field :body, :string
    # Display name for comments captured from Slack, where there is no matching
    # Atlas user to attribute the comment to.
    field :author_name, :string

    belongs_to :blog_post_idea, BlogPostIdea
    belongs_to :author, User

    timestamps()
  end

  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:body, :author_name])
    |> validate_required([:blog_post_idea_id, :body])
    |> update_change(:body, &String.trim/1)
    |> validate_length(:body, min: 1, max: 4_000)
  end
end
