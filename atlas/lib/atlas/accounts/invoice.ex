defmodule Atlas.Accounts.Invoice do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Amounts

  schema "account_invoices" do
    field :external_id, :string
    field :source, :string
    field :number, :string
    field :due_date, :date
    field :amount_value, :decimal
    field :amount_currency, :string
    field :status, :string
    field :stripe_url, :string

    belongs_to :account, Account

    timestamps()
  end

  def changeset(invoice, attrs) do
    invoice
    |> cast(attrs, [
      :external_id,
      :source,
      :number,
      :due_date,
      :amount_value,
      :amount_currency,
      :status,
      :stripe_url
    ])
    |> validate_required([:external_id, :source, :account_id])
    |> update_change(:number, &normalize_optional_string/1)
    |> update_change(:amount_currency, &Amounts.normalize_currency/1)
    |> unique_constraint(:external_id, name: :account_invoices_source_external_id_index)
  end

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
