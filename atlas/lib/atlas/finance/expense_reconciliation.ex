defmodule Atlas.Finance.ExpenseReconciliation do
  @moduledoc false

  alias Atlas.Accounts.Amounts
  alias Atlas.Accounts.ExchangeRates
  alias Atlas.Finance.Config
  alias Atlas.Finance.Query

  @zero Decimal.new("0")

  # This is deliberately an unbounded, server-side query. A reconciliation must
  # either cover every matching transaction or explicitly report why it cannot.
  def build(opts) do
    date_from = Keyword.fetch!(opts, :date_from)
    date_to = Keyword.fetch!(opts, :date_to)
    report_currency = Amounts.normalize_currency(Keyword.get(opts, :currency) || Config.report_currency())

    transactions =
      Query.list_transactions_for_reconciliation(date_from: date_from, date_to: date_to, direction: "debit")

    accounts = Query.list_accounts()

    {included, excluded} = Enum.split_with(transactions, &expense?/1)
    exchange_rates = load_exchange_rates(report_currency, included)
    {converted, unconverted} = convert_transactions(included, report_currency, exchange_rates)

    %{
      period: %{date_from: DateTime.to_date(date_from), date_to: DateTime.to_date(date_to)},
      currency: report_currency,
      total_amount_value: sum(converted, & &1.report_amount_value),
      included_transaction_count: length(converted),
      matching_debit_transaction_count: length(transactions),
      complete?: unconverted == [],
      exchange_rate: exchange_rate_metadata(exchange_rates, report_currency),
      accounts: account_coverage(accounts, converted),
      categories: category_totals(converted),
      currencies: currency_totals(included),
      exclusions: %{
        non_expense_transaction_count: length(excluded),
        unconverted_transaction_count: length(unconverted),
        unconverted_currencies:
          unconverted |> Enum.map(& &1.amount_currency) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort()
      }
    }
  end

  defp expense?(transaction), do: transaction.affects_cash_balance and transaction.affects_runway

  defp load_exchange_rates(report_currency, transactions) do
    currencies =
      transactions
      |> Enum.map(&Amounts.normalize_currency(&1.amount_currency))
      |> Enum.reject(&(is_nil(&1) or &1 == report_currency))
      |> Enum.uniq()

    case ExchangeRates.latest_rates(currencies) do
      {:ok, rates} -> %{rates: rates.rates, published_on: rates.published_on, available?: true}
      {:error, _reason} -> %{rates: %{}, published_on: nil, available?: false}
    end
  end

  defp convert_transactions(transactions, report_currency, exchange_rates) do
    transactions
    |> Enum.reduce({[], []}, fn transaction, {converted, unconverted} ->
      case convert(transaction.amount_value, transaction.amount_currency, report_currency, exchange_rates.rates) do
        {:ok, report_amount_value} ->
          {[%{transaction: transaction, report_amount_value: report_amount_value} | converted], unconverted}

        :error ->
          {converted, [transaction | unconverted]}
      end
    end)
    |> then(fn {converted, unconverted} -> {Enum.reverse(converted), Enum.reverse(unconverted)} end)
  end

  defp convert(%Decimal{} = value, currency, report_currency, _rates) when currency == report_currency, do: {:ok, value}

  defp convert(%Decimal{} = value, currency, "EUR", rates) when is_binary(currency) do
    case Map.get(rates, Amounts.normalize_currency(currency)) do
      %Decimal{} = rate -> {:ok, Decimal.div(value, rate)}
      _ -> :error
    end
  end

  defp convert(%Decimal{} = value, "EUR", report_currency, rates) do
    case Map.get(rates, report_currency) do
      %Decimal{} = rate -> {:ok, Decimal.mult(value, rate)}
      _ -> :error
    end
  end

  defp convert(%Decimal{} = value, currency, report_currency, rates) when is_binary(currency) do
    with %Decimal{} = source_rate <- Map.get(rates, Amounts.normalize_currency(currency)),
         %Decimal{} = target_rate <- Map.get(rates, report_currency) do
      {:ok, value |> Decimal.div(source_rate) |> Decimal.mult(target_rate)}
    else
      _ -> :error
    end
  end

  defp convert(_value, _currency, _report_currency, _rates), do: :error

  defp account_coverage(accounts, converted) do
    converted_by_account = Enum.group_by(converted, & &1.transaction.finance_account_id)

    Enum.map(accounts, fn account ->
      entries = Map.get(converted_by_account, account.id, [])

      %{
        id: account.id,
        name: account.name,
        provider: account.provider,
        source_key: account.source.config_key,
        source_name: account.source.name,
        currency: account.currency,
        last_successful_sync_at: account.source.last_successful_sync_at,
        matching_expense_transaction_count: length(entries),
        total_amount_value: sum(entries, & &1.report_amount_value)
      }
    end)
  end

  defp category_totals(converted) do
    converted
    |> Enum.group_by(fn %{transaction: transaction} ->
      (transaction.category && transaction.category.name) || "Uncategorized"
    end)
    |> Enum.map(fn {name, entries} ->
      %{name: name, transaction_count: length(entries), total_amount_value: sum(entries, & &1.report_amount_value)}
    end)
    |> Enum.sort_by(& &1.total_amount_value, {:desc, Decimal})
  end

  defp currency_totals(transactions) do
    transactions
    |> Enum.group_by(&Amounts.normalize_currency(&1.amount_currency))
    |> Enum.map(fn {currency, entries} ->
      %{
        currency: currency,
        transaction_count: length(entries),
        total_amount_value: sum(entries, &(&1.amount_value || @zero))
      }
    end)
    |> Enum.sort_by(& &1.currency)
  end

  defp exchange_rate_metadata(exchange_rates, report_currency) do
    %{
      basis: "Latest available foreign exchange rates at reconciliation time",
      published_on: exchange_rates.published_on,
      available?: exchange_rates.available?,
      report_currency: report_currency
    }
  end

  defp sum(items, fun), do: Enum.reduce(items, @zero, fn item, total -> Decimal.add(total, fun.(item)) end)
end
