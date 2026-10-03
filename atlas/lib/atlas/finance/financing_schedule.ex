defmodule Atlas.Finance.FinancingSchedule do
  @moduledoc """
  An accountant-imported installment schedule row for a `Financing`.
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Finance.Financing
  alias Atlas.Finance.FinancingSchedule

  @cast_fields ~w(
    financing_id
    sequence
    due_on
    expected_total
    principal_amount
    interest_amount
    rental_amount
    fee_amount
    tax_amount
    option_amount
    deposit_amount
    notes
  )a

  @component_fields ~w(
    principal_amount
    interest_amount
    rental_amount
    fee_amount
    tax_amount
    option_amount
    deposit_amount
  )a

  @derive {
    Flop.Schema,
    filterable: [:financing_id], sortable: [:sequence, :due_on], default_limit: 100, max_limit: 500
  }

  schema "financing_schedules" do
    belongs_to :financing, Financing

    field :sequence, :integer
    field :due_on, :date

    field :expected_total, :decimal

    field :principal_amount, :decimal
    field :interest_amount, :decimal
    field :rental_amount, :decimal
    field :fee_amount, :decimal
    field :tax_amount, :decimal
    field :option_amount, :decimal
    field :deposit_amount, :decimal

    field :notes, :string

    timestamps()
  end

  def changeset(%FinancingSchedule{} = row, attrs) do
    row
    |> cast(attrs, @cast_fields)
    |> validate_required([:financing_id, :sequence, :due_on, :expected_total])
    |> validate_number(:sequence, greater_than: 0)
    |> validate_decimal(:expected_total, :nonneg)
    |> validate_all_components_nonneg()
    |> validate_components_bounded()
    |> foreign_key_constraint(:financing_id)
    |> unique_constraint([:financing_id, :sequence])
    |> translate_db_checks()
  end

  defp validate_all_components_nonneg(changeset) do
    Enum.reduce(@component_fields, changeset, fn field, cs -> validate_decimal(cs, field, :nonneg) end)
  end

  defp validate_components_bounded(changeset) do
    expected = get_field(changeset, :expected_total) || Decimal.new(0)

    total =
      @component_fields
      |> Enum.map(&(get_field(changeset, &1) || Decimal.new(0)))
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

    if Decimal.compare(total, expected) == :gt do
      add_error(changeset, :expected_total, "known components exceed the expected total")
    else
      changeset
    end
  end

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
    |> check_constraint(:expected_total,
      name: :financing_schedules_expected_total_nonneg,
      message: "must be zero or greater"
    )
    |> check_constraint(:expected_total,
      name: :financing_schedules_components_bounded,
      message: "component sum exceeds the expected total"
    )
    |> then(fn cs ->
      Enum.reduce(@component_fields, cs, fn field, acc ->
        check_constraint(acc, field,
          name: :"financing_schedules_#{field}_nonneg",
          message: "must be zero or greater"
        )
      end)
    end)
  end
end
