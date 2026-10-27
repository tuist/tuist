defmodule Atlas.GTM.SocialPostRevision do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.GTM.SocialChannelIdea
  alias Atlas.Users.User

  @statuses ~w(draft approved)

  def statuses, do: @statuses

  schema "social_post_revisions" do
    field :revision_number, :integer
    field :body, :string
    field :notes, :string
    field :status, :string, default: "draft"
    field :created_by_agent, :string

    belongs_to :social_channel_idea, SocialChannelIdea
    belongs_to :author, User

    timestamps()
  end

  def changeset(revision, attrs) do
    revision
    |> cast(attrs, [:body, :notes, :status, :created_by_agent])
    |> Atlas.Changeset.normalize_string_fields([:body, :notes, :created_by_agent])
    |> validate_required([:social_channel_idea_id, :revision_number, :body, :status])
    |> validate_number(:revision_number, greater_than: 0)
    |> validate_length(:body, min: 1, max: 8_000)
    |> validate_length(:notes, max: 2_000)
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:revision_number, name: :social_post_revisions_idea_revision_number_index)
    |> unique_constraint(:status, name: :social_post_revisions_one_approved_per_idea_index)
  end
end
