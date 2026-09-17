defmodule Atlas.Insurance.PolicyMember do
  @moduledoc """
  Half-open coverage interval linking an asset to a policy. An open member
  (covered_to = nil) means the asset is currently declared under the policy.

  A partial unique index enforces at most one open member per (policy, asset)
  pair; multiple policies can cover the same asset concurrently (primary +
  rider).
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Assets.Asset
  alias Atlas.Insurance.Policy
  alias Atlas.Insurance.PolicyMember

  @derive {
    Flop.Schema,
    filterable: [:policy_id, :asset_id],
    sortable: [:covered_from, :covered_to, :declared_value, :inserted_at],
    default_limit: 100,
    max_limit: 500
  }

  schema "insurance_policy_members" do
    belongs_to :policy, Policy, foreign_key: :policy_id
    belongs_to :asset, Asset, foreign_key: :asset_id

    field :declared_value, :decimal
    field :covered_from, :date
    field :covered_to, :date
    field :notes, :string

    timestamps()
  end

  def create_changeset(%PolicyMember{} = member, attrs) do
    member
    |> cast(attrs, [:policy_id, :asset_id, :declared_value, :covered_from, :covered_to, :notes])
    |> validate_required([:policy_id, :asset_id, :declared_value, :covered_from])
    |> validate_decimal_nonneg(:declared_value)
    |> validate_dates_ordered()
    |> foreign_key_constraint(:policy_id)
    |> foreign_key_constraint(:asset_id)
    |> unique_constraint(:asset_id, name: :insurance_policy_members_open_per_asset_per_policy_index)
    |> translate_db_checks()
  end

  def close_changeset(%PolicyMember{} = member, attrs) do
    member
    |> cast(attrs, [:covered_to, :notes])
    |> validate_required([:covered_to])
    |> validate_dates_ordered()
    |> translate_db_checks()
  end

  def update_changeset(%PolicyMember{} = member, attrs) do
    member
    |> cast(attrs, [:declared_value, :notes])
    |> validate_decimal_nonneg(:declared_value)
    |> translate_db_checks()
  end

  defp validate_dates_ordered(changeset) do
    from = get_field(changeset, :covered_from)
    to = get_field(changeset, :covered_to)

    if from && to && Date.before?(to, from) do
      add_error(changeset, :covered_to, "must be on or after the start date")
    else
      changeset
    end
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

  defp translate_db_checks(changeset) do
    changeset
    |> check_constraint(:declared_value,
      name: :insurance_policy_members_declared_value_nonneg,
      message: "must be zero or greater"
    )
    |> check_constraint(:covered_to,
      name: :insurance_policy_members_dates_ordered,
      message: "must be on or after the start date"
    )
  end
end
