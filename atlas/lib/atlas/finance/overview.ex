defmodule Atlas.Finance.Overview do
  @moduledoc false

  import Ecto.Query

  alias Atlas.Accounts
  alias Atlas.Accounts.Amounts
  alias Atlas.Accounts.ExchangeRates
  alias Atlas.Finance.Config
  alias Atlas.Finance.Query
  alias Atlas.Finance.Transaction
  alias Atlas.Repo

  @thirty Decimal.new("30")
  @zero Decimal.new("0")
  @runway_transfer_kinds ~w(internal_transfer treasury_transfer)

  def build(opts \\ []) do
    now =
      opts
      |> Keyword.get(:now, DateTime.utc_now())
      |> DateTime.truncate(:second)

    report_currency = Config.report_currency()
    runway_window_days = Config.runway_window_days()
    runway_window_start = DateTime.add(now, -runway_window_days * 24 * 60 * 60, :second)
    month_window_start = DateTime.add(now, -30 * 24 * 60 * 60, :second)

    accounts = Query.list_accounts()
    sources = Query.list_sources()
    runway_transactions = runway_transactions_since(runway_window_start)

    month_transactions =
      Enum.filter(runway_transactions, &(DateTime.compare(occurred_at(&1), month_window_start) in [:gt, :eq]))

    today = DateTime.to_date(now)
    pipeline_horizon = Date.new!(today.year, 12, 31)

    committed_renewals =
      [limit: 5000, today: today, until: pipeline_horizon]
      |> Accounts.list_upcoming_renewals()
      |> Enum.filter(&(&1.status == "active"))

    exchange_rates =
      load_exchange_rates(report_currency, accounts, runway_transactions, committed_renewals, opts)

    revenue_snapshot = Accounts.revenue_snapshot(Keyword.take(opts, [:exchange_rates_client]))

    available_cash_value =
      sum_account_balances(
        accounts,
        :available_balance_value,
        :available_balance_currency,
        report_currency,
        exchange_rates
      )

    total_balance_value =
      sum_account_balances(accounts, :balance_value, :balance_currency, report_currency, exchange_rates)

    net_30d_value = net_cash_flow(month_transactions, report_currency, exchange_rates)
    runway_window_expense_value = gross_cash_flow(runway_transactions, "debit", report_currency, exchange_rates)
    runway_window_net_burn_value = net_burn(runway_transactions, report_currency, exchange_rates)
    monthly_burn_value = monthly_average(runway_window_net_burn_value, runway_window_days)
    runway_months = runway_months(available_cash_value, monthly_burn_value)

    projected_monthly_revenue_value =
      projected_value(revenue_snapshot.monthly_revenue_eur, report_currency, exchange_rates)

    projected_arr_value = projected_value(revenue_snapshot.estimated_arr_eur, report_currency, exchange_rates)
    projected_monthly_expenses_value = monthly_average(runway_window_expense_value, runway_window_days)
    projected_net_burn_value = projected_net_burn(projected_monthly_expenses_value, projected_monthly_revenue_value)
    projected_runway_months = runway_months(available_cash_value, projected_net_burn_value)

    {committed_pipeline_value, committed_pipeline_count, next_committed_renewal} =
      build_committed_pipeline(committed_renewals, report_currency, exchange_rates)

    cash_plus_committed_runway_months =
      runway_months(Decimal.add(available_cash_value, committed_pipeline_value), projected_net_burn_value)

    runway_uplift_months = runway_uplift(runway_months, projected_runway_months)

    %{
      currency: report_currency,
      available_cash_value: available_cash_value,
      total_balance_value: total_balance_value,
      net_30d_value: net_30d_value,
      monthly_burn_value: monthly_burn_value,
      smoothed_monthly_burn_value: monthly_burn_value,
      runway_months: runway_months,
      trailing_cash_runway_months: runway_months,
      smoothed_cash_runway_months: runway_months,
      projected_monthly_revenue_value: projected_monthly_revenue_value,
      projected_arr_value: projected_arr_value,
      projected_customer_count: revenue_snapshot.renewal_base_count,
      projected_monthly_expenses_value: projected_monthly_expenses_value,
      projected_net_burn_value: projected_net_burn_value,
      projected_runway_months: projected_runway_months,
      plan_adjusted_monthly_burn_value: projected_net_burn_value,
      plan_adjusted_runway_months: projected_runway_months,
      runway_uplift_months: runway_uplift_months,
      committed_pipeline_value: committed_pipeline_value,
      committed_pipeline_count: committed_pipeline_count,
      next_committed_renewal: next_committed_renewal,
      committed_pipeline_horizon: pipeline_horizon,
      cash_plus_committed_runway_months: cash_plus_committed_runway_months,
      runway_window_days: runway_window_days,
      source_count: length(sources),
      account_count: length(accounts),
      transaction_count_30d: length(month_transactions),
      last_synced_at: latest_sync_at(sources)
    }
  end

  defp runway_transactions_since(started_at) do
    Transaction
    |> where([transaction], transaction.affects_runway == true)
    |> where([transaction], is_nil(transaction.kind) or transaction.kind not in ^@runway_transfer_kinds)
    |> where(
      [transaction],
      fragment("coalesce(?, ?, ?)", transaction.settled_at, transaction.booked_at, transaction.provider_updated_at) >=
        ^started_at
    )
    |> Repo.all()
  end

  defp latest_sync_at(sources) do
    sources
    |> Enum.map(& &1.last_successful_sync_at)
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(nil, fn synced_at, latest ->
      case latest do
        nil ->
          synced_at

        %DateTime{} = current_latest ->
          if(DateTime.after?(synced_at, current_latest), do: synced_at, else: current_latest)
      end
    end)
  end

  defp load_exchange_rates(report_currency, accounts, transactions, renewals, opts) do
    currencies =
      accounts
      |> Enum.flat_map(fn account ->
        [account.balance_currency, account.available_balance_currency, account.currency]
      end)
      |> Kernel.++(Enum.flat_map(transactions, fn transaction -> [transaction.amount_currency] end))
      |> Kernel.++(Enum.map(renewals, & &1.currency))
      |> Kernel.++([report_currency])
      |> Enum.map(&Amounts.normalize_currency/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.reject(&(&1 == "EUR"))

    case exchange_rates_client(opts).latest_rates(currencies) do
      {:ok, exchange_rates} -> Map.put(exchange_rates, :report_currency, report_currency)
      {:error, _reason} -> %{published_on: nil, rates: %{}, report_currency: report_currency}
    end
  end

  defp exchange_rates_client(opts) do
    Keyword.get(opts, :exchange_rates_client) ||
      :atlas
      |> Application.get_env(:accounts, [])
      |> Keyword.get(:exchange_rates_client, ExchangeRates)
  end

  defp sum_account_balances(accounts, value_key, currency_key, report_currency, exchange_rates) do
    Enum.reduce(accounts, @zero, fn account, total ->
      case convert(Map.get(account, value_key), Map.get(account, currency_key), report_currency, exchange_rates) do
        {:ok, amount} -> Decimal.add(total, amount)
        :skip -> total
      end
    end)
  end

  defp net_cash_flow(transactions, report_currency, exchange_rates) do
    Enum.reduce(transactions, @zero, fn transaction, total ->
      case convert(transaction.amount_value, transaction.amount_currency, report_currency, exchange_rates) do
        {:ok, amount} ->
          signed_amount =
            case transaction.direction do
              "credit" -> amount
              "debit" -> Decimal.negate(amount)
              _ -> @zero
            end

          Decimal.add(total, signed_amount)

        :skip ->
          total
      end
    end)
  end

  defp gross_cash_flow(transactions, direction, report_currency, exchange_rates) do
    Enum.reduce(transactions, @zero, fn transaction, total ->
      if transaction.direction == direction do
        case convert(transaction.amount_value, transaction.amount_currency, report_currency, exchange_rates) do
          {:ok, amount} -> Decimal.add(total, amount)
          :skip -> total
        end
      else
        total
      end
    end)
  end

  defp net_burn(transactions, report_currency, exchange_rates) do
    transactions
    |> net_cash_flow(report_currency, exchange_rates)
    |> Decimal.negate()
    |> case do
      %Decimal{} = value ->
        case Decimal.compare(value, @zero) do
          :gt -> value
          _ -> @zero
        end
    end
  end

  defp monthly_average(%Decimal{} = value, window_days) do
    months =
      window_days
      |> Decimal.new()
      |> Decimal.div(@thirty)

    Decimal.div(value, months)
  end

  defp projected_value(%Decimal{} = value_eur, report_currency, exchange_rates) do
    case convert(value_eur, "EUR", report_currency, exchange_rates) do
      {:ok, value} -> Decimal.round(value, 2)
      :skip -> @zero
    end
  end

  defp projected_net_burn(%Decimal{} = monthly_expenses, %Decimal{} = monthly_revenue) do
    monthly_expenses
    |> Decimal.sub(monthly_revenue)
    |> case do
      %Decimal{} = value ->
        case Decimal.compare(value, @zero) do
          :gt -> value
          _ -> @zero
        end
    end
  end

  defp runway_months(%Decimal{} = available_cash_value, %Decimal{} = monthly_burn_value) do
    case Decimal.compare(monthly_burn_value, @zero) do
      :gt -> Decimal.div(available_cash_value, monthly_burn_value)
      _ -> nil
    end
  end

  defp convert(nil, _currency, _report_currency, _exchange_rates), do: :skip
  defp convert(_value, nil, _report_currency, _exchange_rates), do: :skip

  defp convert(%Decimal{} = value, currency, report_currency, exchange_rates) do
    source_currency = Amounts.normalize_currency(currency)
    target_currency = Amounts.normalize_currency(report_currency)

    cond do
      is_nil(source_currency) or is_nil(target_currency) ->
        :skip

      source_currency == target_currency ->
        {:ok, value}

      source_currency == "EUR" ->
        multiply_by_rate(value, target_currency, exchange_rates)

      target_currency == "EUR" ->
        divide_by_rate(value, source_currency, exchange_rates)

      true ->
        convert_via_eur(value, source_currency, target_currency, exchange_rates)
    end
  end

  defp multiply_by_rate(value, currency, exchange_rates) do
    case Map.get(exchange_rates.rates, currency) do
      %Decimal{} = rate -> {:ok, Decimal.mult(value, rate)}
      _missing -> :skip
    end
  end

  defp divide_by_rate(value, currency, exchange_rates) do
    case Map.get(exchange_rates.rates, currency) do
      %Decimal{} = rate -> {:ok, Decimal.div(value, rate)}
      _missing -> :skip
    end
  end

  defp convert_via_eur(value, source_currency, target_currency, exchange_rates) do
    with {:ok, eur_value} <- divide_by_rate(value, source_currency, exchange_rates),
         {:ok, target_value} <- multiply_by_rate(eur_value, target_currency, exchange_rates) do
      {:ok, target_value}
    else
      _error -> :skip
    end
  end

  defp occurred_at(transaction), do: Transaction.occurred_at(transaction)

  defp build_committed_pipeline(renewals, report_currency, exchange_rates) do
    {total, count} =
      Enum.reduce(renewals, {@zero, 0}, fn renewal, {total, count} ->
        case convert(renewal.current_value, renewal.currency, report_currency, exchange_rates) do
          {:ok, amount} -> {Decimal.add(total, amount), count + 1}
          :skip -> {total, count}
        end
      end)

    next =
      case List.first(renewals) do
        nil -> nil
        renewal -> %{name: renewal.name, renewal_date: renewal.next_renewal_date}
      end

    {Decimal.round(total, 2), count, next}
  end

  defp runway_uplift(%Decimal{} = base, %Decimal{} = adjusted), do: Decimal.sub(adjusted, base)
  defp runway_uplift(_base, _adjusted), do: nil
end
