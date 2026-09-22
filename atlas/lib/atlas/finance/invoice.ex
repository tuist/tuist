defmodule Atlas.Finance.Invoice do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Amounts
  alias Atlas.Documents.Document
  alias Atlas.Finance.InvoiceLineItem
  alias Atlas.Finance.Transaction

  @statuses ~w(extracted needs_review failed)

  schema "finance_invoices" do
    field :vendor_name, :string
    field :invoice_number, :string
    field :invoice_date, :date
    field :due_date, :date
    field :period_start, :date
    field :period_end, :date
    field :status, :string, default: "extracted"
    field :total_amount_value, :decimal
    field :total_amount_currency, :string
    field :tax_amount_value, :decimal
    field :tax_amount_currency, :string
    field :confidence, :decimal
    field :extracted_by_agent, :string
    field :extracted_at, :utc_datetime
    field :last_error, :string
    field :metadata, :map, default: %{}

    belongs_to :document, Document
    belongs_to :transaction, Transaction, foreign_key: :finance_transaction_id
    has_many :line_items, InvoiceLineItem, foreign_key: :finance_invoice_id, on_replace: :delete

    timestamps()
  end

  def changeset(invoice, attrs) do
    invoice
    |> cast(attrs, [
      :vendor_name,
      :invoice_number,
      :invoice_date,
      :due_date,
      :period_start,
      :period_end,
      :status,
      :total_amount_value,
      :total_amount_currency,
      :tax_amount_value,
      :tax_amount_currency,
      :confidence,
      :extracted_by_agent,
      :extracted_at,
      :last_error,
      :metadata
    ])
    |> update_change(:vendor_name, &normalize_required_string/1)
    |> update_change(:invoice_number, &normalize_optional_string/1)
    |> update_change(:status, &normalize_required_string/1)
    |> update_change(:total_amount_currency, &Amounts.normalize_currency/1)
    |> update_change(:tax_amount_currency, &Amounts.normalize_currency/1)
    |> update_change(:extracted_by_agent, &normalize_optional_string/1)
    |> update_change(:last_error, &normalize_optional_string/1)
    |> validate_required([:vendor_name, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:confidence, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> foreign_key_constraint(:document_id)
    |> foreign_key_constraint(:finance_transaction_id)
    |> unique_constraint(:document_id, name: :finance_invoices_document_id_index)
  end

  def statuses, do: @statuses

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
