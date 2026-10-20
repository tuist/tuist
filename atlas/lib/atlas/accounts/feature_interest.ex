defmodule Atlas.Accounts.FeatureInterest do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.FeatureInterestAccount

  @statuses ~w(open planned shipped declined)

  schema "feature_interests" do
    field :title, :string
    field :canonical_title, :string
    field :status, :string, default: "open"
    field :interest_count, :integer, default: 0
    field :last_interested_at, :utc_datetime
    field :metadata, :map, default: %{}

    has_many :accounts, FeatureInterestAccount

    timestamps()
  end

  def statuses, do: @statuses

  def changeset(interest, attrs) do
    interest
    |> cast(attrs, [:title, :canonical_title, :status, :interest_count, :last_interested_at, :metadata])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:title, :canonical_title, :status])
    |> validate_length(:title, min: 2, max: 160)
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:canonical_title)
  end
end
