defmodule Atlas.Insurance.ClaimAsset do
  @moduledoc """
  Join between an insurance claim and an affected asset with an optional
  per-asset damage amount. A claim with zero rows here is a policy-level
  claim (e.g. cleanup costs at the DC without any specific asset).
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Assets.Asset
  alias Atlas.Insurance.Claim
  alias Atlas.Insurance.ClaimAsset

  schema "insurance_claim_assets" do
    belongs_to :claim, Claim, foreign_key: :claim_id
    belongs_to :asset, Asset, foreign_key: :asset_id

    field :damage_amount, :decimal
    field :notes, :string

    timestamps()
  end

  def create_changeset(%ClaimAsset{} = link, attrs) do
    link
    |> cast(attrs, [:claim_id, :asset_id, :damage_amount, :notes])
    |> validate_required([:claim_id, :asset_id])
    |> validate_decimal_nonneg(:damage_amount)
    |> foreign_key_constraint(:claim_id)
    |> foreign_key_constraint(:asset_id)
    |> unique_constraint([:claim_id, :asset_id])
    |> check_constraint(:damage_amount,
      name: :insurance_claim_assets_damage_nonneg,
      message: "must be zero or greater"
    )
  end

  defp validate_decimal_nonneg(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      case value do
        %Decimal{} = decimal ->
          if Decimal.negative?(decimal), do: [{field, "must be zero or greater"}], else: []

        _other ->
          []
      end
    end)
  end
end
