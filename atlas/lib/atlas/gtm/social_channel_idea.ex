defmodule Atlas.GTM.SocialChannelIdea do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.GTM.SocialPostRevision
  alias Atlas.Users.User

  @statuses ~w(idea approved)

  def statuses, do: @statuses

  schema "social_channel_ideas" do
    field :title, :string
    field :description, :string
    field :status, :string, default: "idea"
    field :created_by_agent, :string

    belongs_to :author, User
    has_many :post_revisions, SocialPostRevision

    timestamps()
  end

  def changeset(idea, attrs) do
    idea
    |> cast(attrs, [:title, :description, :status, :created_by_agent])
    |> Atlas.Changeset.normalize_string_fields([:title, :description, :created_by_agent])
    |> validate_required([:title, :status])
    |> validate_inclusion(:status, @statuses)
  end
end
