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

  @capacity_spill_signal "capacity_spill"

  def roles, do: @roles
  def statuses, do: @statuses

  @doc """
  The evidence signal on a primary that first placement wrote because the
  region the account's traffic preferred had no room for its instance.
  """
  def capacity_spill_signal, do: @capacity_spill_signal

  @doc """
  True iff the row is a guess rather than a decision: a primary first placement
  steered off a full region, which the placer never weighed. The row still holds
  the account to its region against a room reading that moves, but it leaves
  the fast first-placement correction open, exactly as a primary with no row
  behind it does.
  """
  def guess?(%__MODULE__{evidence: %{"signal" => @capacity_spill_signal}}), do: true
  def guess?(%__MODULE__{}), do: false

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
