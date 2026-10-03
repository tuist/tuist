defmodule Atlas.Finance.Transaction do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Amounts
  alias Atlas.Finance.Account
  alias Atlas.Finance.Category

  @derive {Flop.Schema, filterable: [], sortable: [:inserted_at], default_limit: 25, max_limit: 100}

  schema "finance_transactions" do
    field :provider, :string
    field :external_id, :string
    field :status, :string
    field :direction, :string
    field :kind, :string
    field :counterparty_name, :string
    field :description, :string
    field :reference, :string
    field :amount_value, :decimal
    field :amount_currency, :string
    field :local_amount_value, :decimal
    field :local_amount_currency, :string
    field :fee_value, :decimal
    field :fee_currency, :string
    field :running_balance_value, :decimal
    field :running_balance_currency, :string
    field :booked_at, :utc_datetime
    field :settled_at, :utc_datetime
    field :provider_updated_at, :utc_datetime
    field :affects_cash_balance, :boolean, default: true
    field :affects_runway, :boolean, default: true
    field :categorized_at, :utc_datetime
    field :categorization_confidence, :decimal
    field :categorization_reason, :string
    field :categorized_by_agent, :string
    field :metadata, :map, default: %{}
    field :raw, :map, default: %{}

    belongs_to :account, Account, foreign_key: :finance_account_id
    belongs_to :category, Category, foreign_key: :finance_category_id

    timestamps(updated_at: false)
  end

  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [
      :finance_account_id,
      :provider,
      :external_id,
      :status,
      :direction,
      :kind,
      :counterparty_name,
      :description,
      :reference,
      :amount_value,
      :amount_currency,
      :local_amount_value,
      :local_amount_currency,
      :fee_value,
      :fee_currency,
      :running_balance_value,
      :running_balance_currency,
      :booked_at,
      :settled_at,
      :provider_updated_at,
      :affects_cash_balance,
      :affects_runway,
      :finance_category_id,
      :categorized_at,
      :categorization_confidence,
      :categorization_reason,
      :categorized_by_agent,
      :metadata,
      :raw
    ])
    |> validate_required([:finance_account_id, :provider, :external_id, :direction, :amount_value, :amount_currency])
    |> validate_inclusion(:direction, ~w(credit debit))
    |> update_change(:provider, &normalize_string/1)
    |> update_change(:external_id, &normalize_string/1)
    |> update_change(:status, &normalize_optional_string/1)
    |> update_change(:direction, &normalize_string/1)
    |> update_change(:kind, &normalize_optional_string/1)
    |> update_change(:counterparty_name, &normalize_optional_string/1)
    |> update_change(:description, &normalize_optional_string/1)
    |> update_change(:reference, &normalize_optional_string/1)
    |> update_change(:categorized_by_agent, &normalize_optional_string/1)
    |> update_change(:categorization_reason, &normalize_optional_string/1)
    |> update_change(:amount_currency, &Amounts.normalize_currency/1)
    |> update_change(:local_amount_currency, &Amounts.normalize_currency/1)
    |> update_change(:fee_currency, &Amounts.normalize_currency/1)
    |> update_change(:running_balance_currency, &Amounts.normalize_currency/1)
    |> unique_constraint(:external_id, name: :finance_transactions_finance_account_id_external_id_index)
    |> foreign_key_constraint(:finance_account_id)
    |> foreign_key_constraint(:finance_category_id)
  end

  def occurred_at(%__MODULE__{} = transaction) do
    transaction.settled_at || transaction.booked_at || transaction.provider_updated_at || transaction.inserted_at
  end

  defp normalize_string(value) when is_binary(value), do: String.trim(value)
  defp normalize_string(value), do: value

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(value), do: value
end
