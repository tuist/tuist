defmodule Tuist.Kura.PlacerRegion do
  @moduledoc """
  A region the placer decided an account should be served from.

  The primary row is the account's service region; secondary rows are the
  additional regions sustained demand justified. A row in `:retiring` still
  resolves, so nothing re-provisions into a region behind a retirement that is
  still draining.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account

  @roles [:primary, :secondary]
  @statuses [:desired, :retiring]

  schema "kura_placer_regions" do
    field :region, :string
    field :role, Ecto.Enum, values: @roles, default: :primary
    field :status, Ecto.Enum, values: @statuses, default: :desired
    field :evidence, :map, default: %{}

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  def roles, do: @roles
  def statuses, do: @statuses

  def changeset(placer_region, attrs) do
    placer_region
    |> cast(attrs, [:account_id, :region, :role, :status, :evidence])
    |> validate_required([:account_id, :region, :role, :status])
    |> foreign_key_constraint(:account_id)
    |> unique_constraint([:account_id, :region])
    |> unique_constraint(:account_id,
      name: :kura_placer_regions_one_primary_per_account,
      message: "already has a primary region"
    )
  end
end
