defmodule Atlas.GTM.BlogPostIdea do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.GTM.BlogPostIdeaComment
  alias Atlas.Users.User

  @statuses ~w(idea in_progress published)

  def statuses, do: @statuses

  schema "blog_post_ideas" do
    field :title, :string
    field :description, :string
    field :status, :string, default: "idea"
    field :created_by_agent, :string

    # Slack thread the idea was announced in, used to capture replies as comments.
    field :slack_thread_ts, :string

    belongs_to :author, User
    has_many :comments, BlogPostIdeaComment

    timestamps()
  end

  def changeset(idea, attrs) do
    idea
    |> cast(attrs, [:title, :description, :status, :created_by_agent])
    |> normalize_string_fields()
    |> validate_required([:title, :status])
    |> validate_inclusion(:status, @statuses)
  end

  @doc """
  Records the Slack thread an idea was announced in, so later replies can be
  captured back onto the idea.
  """
  def slack_thread_changeset(idea, attrs) do
    cast(idea, attrs, [:slack_thread_ts])
  end

  defp normalize_string_fields(changeset) do
    Enum.reduce([:title, :description, :created_by_agent], changeset, &normalize_field/2)
  end

  defp normalize_field(field, changeset) do
    update_change(changeset, field, fn
      nil ->
        nil

      value when is_binary(value) ->
        value
        |> String.trim()
        |> case do
          "" -> nil
          normalized -> normalized
        end

      value ->
        value
    end)
  end
end
