defmodule Tuist.Kura.EgressLimit do
  @moduledoc """
  A per-account, per-region override of the Kura egress floor and ceiling.

  A region's pair is sized from the box its instances share — the floor is the
  slice an entitled tenant reserves out of the node budget, the ceiling is the
  share of the NIC any one tenant may burst to — so both numbers describe the
  hardware rather than the tenant. Accounts do not share that shape: one
  restoring a large cache from a single CI fan-out wants far more headroom than
  the region-wide ceiling, and one whose bursts crowd out its neighbours on a
  box wants far less.

  A row here replaces one or both of the region's numbers for the account's
  instances *in that region*; no row, or a null column, means the region still
  decides that number there. The scope is a region rather than an account
  because the boxes differ: each declares its own egress budget, so a floor one
  region can keep is one another cannot.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account

  # A floor below 1 Mbit/s is not a reservation anyone can schedule against, and
  # the ceiling shares the bound so the two validate alike. The upper bound is a
  # typo guard rather than a capacity statement: the fleet's fattest shared NIC
  # is ~3 Gbit/s, and the agent clamps a class to the node budget regardless, so
  # anything past 100 Gbit/s is a slipped keystroke rather than an intent.
  @minimum_mbps 1
  @maximum_mbps 100_000

  schema "kura_egress_limits" do
    field :region, :string
    field :floor_mbps, :integer
    field :burst_mbps, :integer

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  def changeset(limit, attrs) do
    limit
    |> cast(attrs, [:account_id, :region, :floor_mbps, :burst_mbps])
    |> validate_required([:account_id, :region])
    |> validate_mbps(:floor_mbps)
    |> validate_mbps(:burst_mbps)
    |> validate_floor_under_burst(:floor_mbps, :burst_mbps)
    |> foreign_key_constraint(:account_id)
    |> unique_constraint([:account_id, :region])
  end

  @doc """
  Validates that `field` holds a rate the shaper can build a class from.

  Shared with the ops form, which validates the same bounds on a schemaless
  changeset before anything is written.
  """
  def validate_mbps(changeset, field) do
    validate_number(changeset, field,
      greater_than_or_equal_to: @minimum_mbps,
      less_than_or_equal_to: @maximum_mbps
    )
  end

  @doc """
  Validates that the pair is a floor under a ceiling.

  A floor above its ceiling is not a stricter limit, it is a guarantee that can
  never be reached: `ceil` is the hard cap, so a class whose rate sits above it
  is throttled below its own floor for ever. Nothing downstream objects — tc
  installs such a class without complaint (measured) — so the form is the only
  place an operator finds out at all.

  Only checked when both numbers are present in the same changeset: a pair the
  operator stated both halves of is theirs to keep coherent. A lone override is
  not an inverted pair — the half the operator left blank is a default, and
  `Tuist.Kura.EgressLimits` resolves it *to* the stated half rather than against
  it.
  """
  def validate_floor_under_burst(changeset, floor_field, burst_field) do
    floor = get_field(changeset, floor_field)
    burst = get_field(changeset, burst_field)

    if is_integer(floor) and is_integer(burst) and floor > burst do
      add_error(changeset, floor_field, "must not exceed the ceiling")
    else
      changeset
    end
  end

  def minimum_mbps, do: @minimum_mbps
  def maximum_mbps, do: @maximum_mbps
end
