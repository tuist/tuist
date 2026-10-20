defmodule Atlas.Insurance.Policy do
  @moduledoc """
  An insurance policy covering one or more hardware assets. Each policy has a
  headline coverage amount (`sum_insured`) plus provisional headroom, and a
  set of dated members that declare which assets are under the policy at any
  point in time.

  Policies are agreements, not taxonomies. Different `product` values live
  alongside each other (electronics for the data center, laptops for the
  office, transit riders) without any per-policy category enum.
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Insurance.Claim
  alias Atlas.Insurance.Policy
  alias Atlas.Insurance.PolicyDocument
  alias Atlas.Insurance.PolicyMember

  @statuses ~w(quoted active expired cancelled terminated)
  @premium_frequencies ~w(annual quarterly monthly)

  @creation_fields ~w(
    provider
    product
    reference
    currency
    sum_insured
    provisional_cover_pct
    annual_premium
    premium_frequency
    deductible_per_claim
    deductible_cap
    mobile_use_pct
    cleanup_pct
    cleanup_min
    cleanup_max
    movement_pct
    movement_min
    movement_max
    covers_data
    covers_software
    covers_dongles
    covers_leased
    covers_third_party_owned
    starts_on
    ends_on
    quote_valid_until
    previous_policy_id
    notes
  )a

  @metadata_fields @creation_fields -- ~w(previous_policy_id)a

  @derive {
    Flop.Schema,
    filterable: [:status, :provider, :product],
    sortable: [:provider, :product, :starts_on, :ends_on, :annual_premium, :inserted_at],
    default_limit: 50,
    max_limit: 200
  }

  schema "insurance_policies" do
    field :provider, :string
    field :product, :string
    field :reference, :string

    field :currency, :string
    field :sum_insured, :decimal
    field :provisional_cover_pct, :integer, default: 0

    field :annual_premium, :decimal, default: Decimal.new(0)
    field :premium_frequency, :string, default: "annual"

    field :deductible_per_claim, :decimal, default: Decimal.new(0)
    field :deductible_cap, :decimal

    field :mobile_use_pct, :integer, default: 0

    field :cleanup_pct, :integer, default: 0
    field :cleanup_min, :decimal
    field :cleanup_max, :decimal

    field :movement_pct, :integer, default: 0
    field :movement_min, :decimal
    field :movement_max, :decimal

    field :covers_data, :boolean, default: false
    field :covers_software, :boolean, default: false
    field :covers_dongles, :boolean, default: false
    field :covers_leased, :boolean, default: false
    field :covers_third_party_owned, :boolean, default: false

    field :starts_on, :date
    field :ends_on, :date
    field :quote_valid_until, :date

    field :status, :string, default: "quoted"

    belongs_to :previous_policy, Policy, foreign_key: :previous_policy_id

    has_many :members, PolicyMember
    has_many :claims, Claim
    has_many :document_links, PolicyDocument
    has_many :documents, through: [:document_links, :document]

    field :notes, :string

    timestamps()
  end

  def statuses, do: @statuses
  def premium_frequencies, do: @premium_frequencies

  def create_changeset(%Policy{} = policy, attrs) do
    policy
    |> cast(attrs, @creation_fields)
    |> validate_required([:provider, :product, :currency, :sum_insured])
    |> common_validations()
  end

  def metadata_changeset(%Policy{} = policy, attrs) do
    policy
    |> cast(attrs, @metadata_fields)
    |> common_validations()
  end

  def status_changeset(%Policy{} = policy, attrs) do
    policy
    |> cast(attrs, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
    |> translate_db_checks()
  end

  defp common_validations(changeset) do
    changeset
    |> update_change(:provider, &normalize_optional_string/1)
    |> update_change(:product, &normalize_optional_string/1)
    |> update_change(:reference, &normalize_optional_string/1)
    |> update_change(:currency, &normalize_currency/1)
    |> validate_inclusion(:premium_frequency, @premium_frequencies)
    |> validate_currency(:currency)
    |> validate_decimal(:sum_insured, :nonneg)
    |> validate_decimal(:annual_premium, :nonneg)
    |> validate_decimal(:deductible_per_claim, :nonneg)
    |> validate_decimal(:deductible_cap, :nonneg)
    |> validate_number(:provisional_cover_pct, greater_than_or_equal_to: 0, less_than_or_equal_to: 200)
    |> validate_number(:mobile_use_pct, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:cleanup_pct, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:movement_pct, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_dates_ordered()
    |> foreign_key_constraint(:previous_policy_id)
    |> translate_db_checks()
  end

  defp validate_dates_ordered(changeset) do
    starts = get_field(changeset, :starts_on)
    ends = get_field(changeset, :ends_on)

    if starts && ends && Date.before?(ends, starts) do
      add_error(changeset, :ends_on, "must be on or after the start date")
    else
      changeset
    end
  end

  defp translate_db_checks(changeset) do
    changeset
    |> check_constraint(:status,
      name: :insurance_policies_status_check,
      message: "is not a valid status"
    )
    |> check_constraint(:premium_frequency,
      name: :insurance_policies_frequency_check,
      message: "is not a valid premium frequency"
    )
    |> check_constraint(:sum_insured,
      name: :insurance_policies_sum_insured_nonneg,
      message: "must be zero or greater"
    )
    |> check_constraint(:provisional_cover_pct,
      name: :insurance_policies_provisional_cover_pct_range,
      message: "must be between 0 and 200"
    )
    |> check_constraint(:annual_premium,
      name: :insurance_policies_annual_premium_nonneg,
      message: "must be zero or greater"
    )
    |> check_constraint(:deductible_per_claim,
      name: :insurance_policies_deductible_per_claim_nonneg,
      message: "must be zero or greater"
    )
    |> check_constraint(:deductible_cap,
      name: :insurance_policies_deductible_cap_nonneg,
      message: "must be zero or greater"
    )
    |> check_constraint(:ends_on,
      name: :insurance_policies_dates_ordered,
      message: "must be on or after the start date"
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

  @doc """
  Effective coverage cap: `sum_insured × (1 + provisional_cover_pct/100)`.
  """
  def effective_cap(%Policy{sum_insured: sum, provisional_cover_pct: pct}) when not is_nil(sum) do
    Decimal.mult(sum, Decimal.div(Decimal.new(100 + pct), Decimal.new(100)))
  end

  def effective_cap(_), do: nil
end
