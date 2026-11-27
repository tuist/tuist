defmodule Atlas.GTM.SocialPublication do
  @moduledoc """
  A post or thread Atlas publishes to one account at `scheduled_at`, once a
  person approved its current `revision`. `published_ids` holds the posts X
  created so far, in thread order, so a failed thread resumes after them.
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.GTM.SocialAccount
  alias Atlas.GTM.SocialPostRevision
  alias Atlas.Users.User

  @statuses ~w(draft approved publishing published failed cancelled)

  def statuses, do: @statuses

  schema "social_publications" do
    field :items, {:array, :map}, default: []
    field :scheduled_at, :utc_datetime
    field :status, :string, default: "draft"
    field :revision, :integer, default: 1
    field :approved_revision, :integer
    field :approved_at, :utc_datetime
    # %{media_id => %{"byte_size" => integer, "sha256" => hex}} as approved.
    field :approved_media, :map
    field :published_ids, {:array, :string}, default: []
    field :published_at, :utc_datetime
    field :last_error, :string

    belongs_to :social_account, SocialAccount
    belongs_to :social_post_revision, SocialPostRevision
    belongs_to :approved_by, User
    belongs_to :created_by, User

    timestamps(type: :utc_datetime)
  end

  def changeset(publication, attrs) do
    publication
    |> cast(attrs, [:items, :scheduled_at, :social_account_id, :social_post_revision_id])
    |> validate_required([:items, :scheduled_at, :social_account_id])
    |> validate_length(:items, min: 1, max: 25)
  end

  def editable?(%__MODULE__{status: status, published_ids: ids}), do: status in ~w(draft approved failed) and ids == []

  @doc """
  A publish that stopped without finishing, such as when its node went away.
  X may have created some of its posts, so a person checks and approves again.
  """
  def stalled?(%__MODULE__{status: "publishing", updated_at: updated_at}),
    do: DateTime.diff(DateTime.utc_now(), updated_at, :minute) >= 30

  def stalled?(_publication), do: false

  def url(%__MODULE__{published_ids: [id | _]}), do: "https://x.com/i/web/status/" <> id
  def url(_publication), do: nil
end
