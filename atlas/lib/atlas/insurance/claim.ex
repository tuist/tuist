defmodule Atlas.Insurance.Claim do
  @moduledoc """
  A claim filed against a policy. An event can hit multiple assets, so
  affected-asset links live in `Atlas.Insurance.ClaimAsset`.
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Insurance.Claim
  alias Atlas.Insurance.ClaimAsset
  alias Atlas.Insurance.Policy

  @statuses ~w(draft submitted approved paid rejected withdrawn)
  @incident_types ~w(theft damage fire water loss other)

  @creation_fields ~w(
    policy_id
    claim_reference
    incident_on
    incident_type
    reported_on
    status
    claimed_amount
    payout_amount
    deductible_applied
    notes
  )a

  @update_fields @creation_fields -- ~w(policy_id)a

  @derive {
    Flop.Schema,
    filterable: [:status, :incident_type, :policy_id],
    sortable: [:incident_on, :reported_on, :status, :claimed_amount, :payout_amount, :inserted_at],
    default_limit: 50,
    max_limit: 200
  }

  schema "insurance_claims" do
    belongs_to :policy, Policy, foreign_key: :policy_id

    field :claim_reference, :string

    field :incident_on, :date
    field :incident_type, :string
    field :reported_on, :date
    field :status, :string, default: "draft"

    field :claimed_amount, :decimal
    field :payout_amount, :decimal
    field :deductible_applied, :decimal

    field :notes, :string

    has_many :assets, ClaimAsset

    timestamps()
  end

  def statuses, do: @statuses
  def incident_types, do: @incident_types

  def create_changeset(%Claim{} = claim, attrs) do
    claim
    |> cast(attrs, @creation_fields)
    |> validate_required([:policy_id, :incident_on, :incident_type])
    |> common_validations()
  end

  def update_changeset(%Claim{} = claim, attrs) do
    claim
    |> cast(attrs, @update_fields)
    |> validate_required([:incident_on, :incident_type])
    |> common_validations()
  end

  defp common_validations(changeset) do
    changeset
    |> update_change(:claim_reference, &normalize_optional_string/1)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:incident_type, @incident_types)
    |> validate_decimal_nonneg(:claimed_amount)
    |> validate_decimal_nonneg(:payout_amount)
    |> validate_decimal_nonneg(:deductible_applied)
    |> validate_dates_ordered()
    |> foreign_key_constraint(:policy_id)
    |> translate_db_checks()
  end

  defp validate_dates_ordered(changeset) do
    incident = get_field(changeset, :incident_on)
    reported = get_field(changeset, :reported_on)

    if incident && reported && Date.before?(reported, incident) do
      add_error(changeset, :reported_on, "must be on or after the incident date")
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
    |> check_constraint(:status,
      name: :insurance_claims_status_check,
      message: "is not a valid status"
    )
    |> check_constraint(:incident_type,
      name: :insurance_claims_incident_type_check,
      message: "is not a valid incident type"
    )
    |> check_constraint(:claimed_amount,
      name: :insurance_claims_amounts_nonneg,
      message: "must be zero or greater"
    )
    |> check_constraint(:reported_on,
      name: :insurance_claims_reported_after_incident,
      message: "must be on or after the incident date"
    )
  end

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
