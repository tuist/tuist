defmodule Atlas.Finance.Account do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Amounts
  alias Atlas.Finance.Source
  alias Atlas.Finance.Transaction

  schema "finance_accounts" do
    field :provider, :string
    field :external_id, :string
    field :name, :string
    field :account_type, :string
    field :account_subtype, :string
    field :currency, :string
    field :iban, :string
    field :bic, :string
    field :main, :boolean, default: false
    field :status, :string
    field :balance_value, :decimal
    field :balance_currency, :string
    field :available_balance_value, :decimal
    field :available_balance_currency, :string
    field :transactions_synced_at, :utc_datetime
    field :refreshed_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :source, Source, foreign_key: :finance_source_id
    has_many :transactions, Transaction, foreign_key: :finance_account_id

    timestamps()
  end

  def changeset(account, attrs) do
    account
    |> cast(attrs, [
      :finance_source_id,
      :provider,
      :external_id,
      :name,
      :account_type,
      :account_subtype,
      :currency,
      :iban,
      :bic,
      :main,
      :status,
      :balance_value,
      :balance_currency,
      :available_balance_value,
      :available_balance_currency,
      :transactions_synced_at,
      :refreshed_at,
      :metadata
    ])
    |> validate_required([:finance_source_id, :provider, :external_id, :name])
    |> update_change(:provider, &normalize_string/1)
    |> update_change(:external_id, &normalize_string/1)
    |> update_change(:name, &normalize_string/1)
    |> update_change(:account_type, &normalize_optional_string/1)
    |> update_change(:account_subtype, &normalize_optional_string/1)
    |> update_change(:status, &normalize_optional_string/1)
    |> update_change(:currency, &Amounts.normalize_currency/1)
    |> update_change(:balance_currency, &Amounts.normalize_currency/1)
    |> update_change(:available_balance_currency, &Amounts.normalize_currency/1)
    |> unique_constraint(:external_id, name: :finance_accounts_finance_source_id_external_id_index)
    |> foreign_key_constraint(:finance_source_id)
  end

  def provider_label(%__MODULE__{provider: provider}), do: provider_label(provider)

  def provider_label(provider) when is_binary(provider) do
    provider
    |> String.trim()
    |> String.replace("_", " ")
    |> String.capitalize()
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
