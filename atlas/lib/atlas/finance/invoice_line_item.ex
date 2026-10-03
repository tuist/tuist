defmodule Atlas.Finance.InvoiceLineItem do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Amounts
  alias Atlas.Finance.Category
  alias Atlas.Finance.Invoice

  schema "finance_invoice_line_items" do
    field :description, :string
    field :cost_type, :string
    field :amount_value, :decimal
    field :amount_currency, :string
    field :quantity, :decimal
    field :unit_amount_value, :decimal
    field :unit_amount_currency, :string
    field :service_period_start, :date
    field :service_period_end, :date
    field :confidence, :decimal
    field :metadata, :map, default: %{}

    belongs_to :invoice, Invoice, foreign_key: :finance_invoice_id
    belongs_to :category, Category, foreign_key: :finance_category_id

    timestamps()
  end

  def changeset(line_item, attrs) do
    line_item
    |> cast(attrs, [
      :description,
      :cost_type,
      :amount_value,
      :amount_currency,
      :quantity,
      :unit_amount_value,
      :unit_amount_currency,
      :service_period_start,
      :service_period_end,
      :confidence,
      :metadata
    ])
    |> update_change(:description, &normalize_required_string/1)
    |> update_change(:cost_type, &normalize_optional_string/1)
    |> update_change(:amount_currency, &Amounts.normalize_currency/1)
    |> update_change(:unit_amount_currency, &Amounts.normalize_currency/1)
    |> validate_required([:finance_invoice_id, :description, :amount_value, :amount_currency])
    |> validate_number(:confidence, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> foreign_key_constraint(:finance_invoice_id)
    |> foreign_key_constraint(:finance_category_id)
  end

  defp normalize_required_string(value) when is_binary(value), do: String.trim(value)
  defp normalize_required_string(value), do: value

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(value), do: value
end
