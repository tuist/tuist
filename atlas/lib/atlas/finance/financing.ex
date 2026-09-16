defmodule Atlas.Finance.Financing do
  @moduledoc """
  A financing arrangement (loan or lease) funding one or more hardware assets.

  The `type` describes the legal shape of the contract. `accounting_treatment`
  is an accountant-approved attribute persisted separately; it drives how
  pool cost recognition treats the arrangement in phase B+ but has no effect
  on ownership state on the linked assets.

  Design in `docs/hardware-financing-and-attribution-proposal.md`.
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Finance.Financing
  alias Atlas.Finance.FinancingDocument
  alias Atlas.Finance.FinancingLine
  alias Atlas.Finance.FinancingPayment
  alias Atlas.Finance.FinancingSchedule

  @types ~w(loan lease_with_purchase_option lease_without_purchase_option)
  @accounting_treatments ~w(capitalized expensed undetermined)
  @statuses ~w(active paid_off option_exercised returned terminated)

  @creation_fields ~w(
    type
    accounting_treatment
    treatment_evidence
    provider
    supplier
    reference
    disbursement_or_commencement_on
    term_months
    currency
    undiscounted_commitment
    initial_liability
    interest_rate
    principal_amount
    purchase_option_amount
    purchase_option_available_from
    notes
  )a

  @metadata_fields ~w(
    provider
    supplier
    reference
    disbursement_or_commencement_on
    term_months
    interest_rate
    undiscounted_commitment
    initial_liability
    purchase_option_amount
    purchase_option_available_from
    notes
  )a

  @derive {
    Flop.Schema,
    filterable: [:type, :status, :provider, :accounting_treatment],
    sortable: [:provider, :disbursement_or_commencement_on, :inserted_at],
    default_limit: 50,
    max_limit: 200
  }

  schema "financings" do
    field :type, :string
    field :accounting_treatment, :string, default: "undetermined"
    field :treatment_evidence, :string

    field :provider, :string
    field :supplier, :string
    field :reference, :string
    field :disbursement_or_commencement_on, :date
    field :term_months, :integer
    field :currency, :string

    field :undiscounted_commitment, :decimal, default: Decimal.new(0)
    field :initial_liability, :decimal
    field :interest_rate, :decimal

    field :principal_amount, :decimal

    field :purchase_option_amount, :decimal
    field :purchase_option_available_from, :date

    field :status, :string, default: "active"

    field :notes, :string

    has_many :schedules, FinancingSchedule
    has_many :lines, FinancingLine
    has_many :payments, FinancingPayment
    has_many :documents, FinancingDocument

    timestamps()
  end

  def types, do: @types
  def accounting_treatments, do: @accounting_treatments
  def statuses, do: @statuses

  @doc """
  Changeset for creating a new financing arrangement.
  """
  def create_changeset(%Financing{} = financing, attrs) do
    financing
    |> cast(attrs, @creation_fields)
    |> validate_required([
      :type,
      :provider,
      :disbursement_or_commencement_on,
      :currency
    ])
    |> common_validations()
    |> validate_type_specific()
  end

  @doc """
  Metadata-only edits. Does not change type, currency, status, or the
  treatment/evidence pair (those go through dedicated operations in
  `Atlas.Finance.Financings`).
  """
  def metadata_changeset(%Financing{} = financing, attrs) do
    financing
    |> cast(attrs, @metadata_fields)
    |> common_validations()
  end

  @doc """
  Applies a treatment change with matching evidence. Consumed by
  `Atlas.Finance.Financings.set_accounting_treatment/3`.
  """
  def treatment_changeset(%Financing{} = financing, attrs) do
    financing
    |> cast(attrs, [:accounting_treatment, :treatment_evidence])
    |> validate_required([:accounting_treatment])
    |> validate_inclusion(:accounting_treatment, @accounting_treatments)
  end

  @doc """
  Lifecycle changeset used by status transitions. Not exposed publicly.
  """
  def status_changeset(%Financing{} = financing, attrs) do
    financing
    |> cast(attrs, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end

  defp common_validations(changeset) do
    changeset
    |> update_change(:provider, &normalize_optional_string/1)
    |> update_change(:supplier, &normalize_optional_string/1)
    |> update_change(:reference, &normalize_optional_string/1)
    |> update_change(:treatment_evidence, &normalize_optional_string/1)
    |> update_change(:currency, &normalize_currency/1)
    |> validate_inclusion(:type, @types)
    |> validate_inclusion(:accounting_treatment, @accounting_treatments)
    |> validate_currency(:currency)
    |> validate_number(:term_months, greater_than: 0)
    |> validate_decimal(:undiscounted_commitment, :nonneg)
    |> validate_decimal(:initial_liability, :nonneg)
    |> validate_decimal(:principal_amount, :nonneg)
    |> validate_decimal(:purchase_option_amount, :nonneg)
    |> translate_db_checks()
  end

  defp validate_type_specific(changeset) do
    type = get_field(changeset, :type)
    principal = get_field(changeset, :principal_amount)
    option = get_field(changeset, :purchase_option_amount)

    changeset =
      case {type, principal} do
        {"loan", nil} ->
          add_error(changeset, :principal_amount, "is required for loans")

        {t, principal} when t != "loan" and not is_nil(principal) ->
          add_error(changeset, :principal_amount, "must be null for leases")

        _ ->
          changeset
      end

    case {type, option} do
      {t, option} when t != "lease_with_purchase_option" and not is_nil(option) ->
        add_error(
          changeset,
          :purchase_option_amount,
          "is only allowed for lease_with_purchase_option"
        )

      _ ->
        changeset
    end
  end

  defp translate_db_checks(changeset) do
    changeset
    |> check_constraint(:type, name: :financings_type_check, message: "is not a valid type")
    |> check_constraint(:accounting_treatment,
      name: :financings_treatment_check,
      message: "is not a valid accounting treatment"
    )
    |> check_constraint(:status, name: :financings_status_check, message: "is not a valid status")
    |> check_constraint(:term_months,
      name: :financings_term_positive,
      message: "must be greater than zero"
    )
    |> check_constraint(:undiscounted_commitment,
      name: :financings_undiscounted_nonneg,
      message: "must be zero or greater"
    )
    |> check_constraint(:initial_liability,
      name: :financings_initial_liability_nonneg,
      message: "must be zero or greater"
    )
    |> check_constraint(:principal_amount,
      name: :financings_principal_nonneg,
      message: "must be zero or greater"
    )
    |> check_constraint(:purchase_option_amount,
      name: :financings_option_amount_nonneg,
      message: "must be zero or greater"
    )
    |> check_constraint(:principal_amount,
      name: :financings_principal_iff_loan,
      message: "must be set for loans and null for leases"
    )
    |> check_constraint(:purchase_option_amount,
      name: :financings_option_amount_iff_option_lease,
      message: "is only allowed for lease_with_purchase_option"
    )
    |> check_constraint(:status,
      name: :financings_status_option_exercised_iff_option_lease,
      message: "option-exercised is only valid for lease_with_purchase_option"
    )
    |> check_constraint(:status,
      name: :financings_status_returned_iff_lease,
      message: "returned status is not valid for loans"
    )
  end

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_currency(nil), do: nil
  defp normalize_currency(value) when is_binary(value), do: value |> String.trim() |> String.upcase()

  defp validate_currency(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      cond do
        is_nil(value) -> []
        supported_currency?(value) -> []
        true -> [{field, "is not a supported ISO 4217 currency code"}]
      end
    end)
  end

  defp supported_currency?(code) do
    Money.Currency.exists?(code)
  rescue
    _ -> false
  end

  defp validate_decimal(changeset, field, :nonneg) do
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
