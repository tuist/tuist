defmodule Atlas.Finance.FinancingPayment do
  @moduledoc """
  A concrete payment matching a `Finance.Transaction` to a `Financing`,
  with a decomposition into principal / interest / rental / fee / tax /
  option / deposit / unclassified components in the settlement currency.

  Reconciliation contract:

  * All known components are >= 0 (DB check).
  * The sum of known components (NULLs treated as 0) is at most
    `settlement_amount` for every status (DB check).
  * `:resolved` requires the sum to equal `settlement_amount` exactly and
    `unclassified_amount` to be null or zero (DB check).

  Cross-currency: when `settlement_currency` differs from the parent
  financing's currency, the payment stays `:partial` and the components are
  in the settlement currency.
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Finance.Financing
  alias Atlas.Finance.FinancingPayment
  alias Atlas.Finance.FinancingSchedule
  alias Atlas.Finance.Transaction

  @directions ~w(debit credit)
  @resolution_statuses ~w(resolved unresolved partial)

  @component_fields ~w(
    principal_amount
    interest_amount
    rental_amount
    fee_amount
    tax_amount
    option_amount
    deposit_amount
    unclassified_amount
  )a

  @cast_fields ~w(
    financing_id
    finance_transaction_id
    schedule_id
    paid_on
    direction
    settlement_amount
    settlement_currency
    resolution_status
    notes
  )a ++ @component_fields

  @derive {
    Flop.Schema,
    filterable: [:financing_id, :direction, :resolution_status],
    sortable: [:paid_on, :inserted_at],
    default_limit: 100,
    max_limit: 500
  }

  schema "financing_payments" do
    belongs_to :financing, Financing
    belongs_to :finance_transaction, Transaction, foreign_key: :finance_transaction_id
    belongs_to :schedule, FinancingSchedule, foreign_key: :schedule_id

    field :paid_on, :date
    field :direction, :string

    field :settlement_amount, :decimal
    field :settlement_currency, :string

    field :principal_amount, :decimal
    field :interest_amount, :decimal
    field :rental_amount, :decimal
    field :fee_amount, :decimal
    field :tax_amount, :decimal
    field :option_amount, :decimal
    field :deposit_amount, :decimal
    field :unclassified_amount, :decimal

    field :resolution_status, :string, default: "unresolved"
    field :notes, :string

    timestamps()
  end

  def component_fields, do: @component_fields
  def directions, do: @directions
  def resolution_statuses, do: @resolution_statuses

  def changeset(%FinancingPayment{} = payment, attrs) do
    payment
    |> cast(attrs, @cast_fields)
    |> validate_required([
      :financing_id,
      :finance_transaction_id,
      :paid_on,
      :direction,
      :settlement_amount,
      :settlement_currency,
      :resolution_status
    ])
    |> validate_inclusion(:direction, @directions)
    |> validate_inclusion(:resolution_status, @resolution_statuses)
    |> update_change(:settlement_currency, &normalize_currency/1)
    |> validate_decimal(:settlement_amount, :nonneg)
    |> validate_components_nonneg()
    |> validate_components_bounded()
    |> validate_resolved_reconciles()
    |> foreign_key_constraint(:financing_id)
    |> foreign_key_constraint(:finance_transaction_id)
    |> unique_constraint(:finance_transaction_id)
    |> translate_db_checks()
  end

  defp validate_components_nonneg(changeset) do
    Enum.reduce(@component_fields, changeset, fn field, cs ->
      validate_decimal(cs, field, :nonneg)
    end)
  end

  defp validate_components_bounded(changeset) do
    settlement = get_field(changeset, :settlement_amount)

    if is_nil(settlement) do
      changeset
    else
      total = component_sum(changeset)

      if Decimal.compare(total, settlement) == :gt do
        add_error(changeset, :settlement_amount, "component sum exceeds the settlement amount")
      else
        changeset
      end
    end
  end

  defp validate_resolved_reconciles(changeset) do
    status = get_field(changeset, :resolution_status)
    settlement = get_field(changeset, :settlement_amount)
    unclassified = get_field(changeset, :unclassified_amount) || Decimal.new(0)

    cond do
      status != "resolved" ->
        changeset

      is_nil(settlement) ->
        add_error(changeset, :settlement_amount, "is required for a resolved payment")

      not decimal_zero?(unclassified) ->
        add_error(
          changeset,
          :unclassified_amount,
          "must be zero when the payment is resolved"
        )

      true ->
        classified_sum =
          @component_fields
          |> List.delete(:unclassified_amount)
          |> Enum.map(&(get_field(changeset, &1) || Decimal.new(0)))
          |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

        if Decimal.equal?(classified_sum, settlement) do
          changeset
        else
          add_error(
            changeset,
            :resolution_status,
            "known components do not sum to the settlement amount"
          )
        end
    end
  end

  defp component_sum(changeset) do
    @component_fields
    |> Enum.map(&(get_field(changeset, &1) || Decimal.new(0)))
    |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
  end

  defp decimal_zero?(%Decimal{} = d), do: Decimal.equal?(d, Decimal.new(0))
  defp decimal_zero?(_), do: true

  defp normalize_currency(nil), do: nil
  defp normalize_currency(value) when is_binary(value), do: value |> String.trim() |> String.upcase()

  defp validate_decimal(changeset, field, :nonneg) do
    validate_change(changeset, field, fn ^field, value ->
      case value do
        %Decimal{} = d ->
          if Decimal.negative?(d), do: [{field, "must be zero or greater"}], else: []

        _ ->
          []
      end
    end)
  end

  defp translate_db_checks(changeset) do
    changeset
    |> check_constraint(:direction,
      name: :financing_payments_direction_check,
      message: "is not a valid direction"
    )
    |> check_constraint(:resolution_status,
      name: :financing_payments_resolution_status_check,
      message: "is not a valid resolution status"
    )
    |> check_constraint(:settlement_amount,
      name: :financing_payments_settlement_nonneg,
      message: "must be zero or greater"
    )
    |> check_constraint(:settlement_amount,
      name: :financing_payments_components_bounded,
      message: "component sum exceeds the settlement amount"
    )
    |> check_constraint(:resolution_status,
      name: :financing_payments_resolved_reconciles,
      message: "resolved payments must fully reconcile the settlement"
    )
    |> then(fn cs ->
      Enum.reduce(@component_fields, cs, fn field, acc ->
        check_constraint(acc, field,
          name: :"financing_payments_#{field}_nonneg",
          message: "must be zero or greater"
        )
      end)
    end)
    |> check_constraint(:schedule_id,
      name: :financing_payments_schedule_fk,
      message: "must reference a schedule row on the same financing"
    )
  end
end
