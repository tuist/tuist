defmodule Atlas.Finance.FinancingLine do
  @moduledoc """
  Per-asset allocation for a `Financing`. `share_bps` is in basis points;
  the sum across all lines for a financing must equal 10_000. That invariant
  is enforced transactionally by `Atlas.Finance.Financings.set_lines/2`, not
  at the DB level, because a single row cannot express the sum-must-equal
  constraint without a trigger.
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Assets.Asset
  alias Atlas.Finance.Financing
  alias Atlas.Finance.FinancingLine

  @derive {
    Flop.Schema,
    filterable: [:financing_id, :asset_id], sortable: [:inserted_at], default_limit: 100, max_limit: 500
  }

  schema "financing_lines" do
    belongs_to :financing, Financing
    belongs_to :asset, Asset

    field :share_bps, :integer
    field :notes, :string

    timestamps()
  end

  def changeset(%FinancingLine{} = line, attrs) do
    line
    |> cast(attrs, [:financing_id, :asset_id, :share_bps, :notes])
    |> validate_required([:financing_id, :asset_id, :share_bps])
    |> validate_number(:share_bps, greater_than_or_equal_to: 1, less_than_or_equal_to: 10_000)
    |> foreign_key_constraint(:financing_id)
    |> foreign_key_constraint(:asset_id)
    |> unique_constraint([:financing_id, :asset_id])
    |> check_constraint(:share_bps,
      name: :financing_lines_share_bps_range,
      message: "must be between 1 and 10000"
    )
  end
end
