defmodule Atlas.Finance.Runway do
  @moduledoc false

  import Ecto.Query

  alias Atlas.Accounts.Amounts
  alias Atlas.Accounts.ExchangeRates
  alias Atlas.Finance.Config
  alias Atlas.Finance.Query
  alias Atlas.Finance.Transaction
  alias Atlas.Repo

  @default_history_days 180
  @weekly_step_days 7
  @monthly_step_days 30
  @monthly_step_threshold_days 90
  @trend_window_days 30
  @zero Decimal.new("0")
  @thirty Decimal.new("30")

  # The `window` is the shared analytics context for the cash overview charts:
  # `%{now, today, currency, burn_window_days, history_days, step_days,
  # account_count, dates, current_balance, daily_net_flow}`. It is built once per
  # request with `window/1`, then handed to the per-metric `*_analytics/1`
  # functions so the accounts, transactions, and exchange rates load only once.
  #
  # Each `*_analytics/1` returns a metric map mirroring the Tuist dashboards:
  # `%{currency, dates, values, value, trend}`, where `trend` is the percentage
  # change versus roughly a month earlier (`nil` when it cannot be computed).

  @doc """
  Loads the shared data backing the cash overview charts for the given window.

  Options:

    * `:history_days` — how far back the buckets reach (default #{@default_history_days}).
    * `:step_days` — bucket size; defaults to weekly for short ranges and monthly
      for ranges longer than #{@monthly_step_threshold_days} days.
    * `:now` — reference timestamp, useful in tests.

  Pass the result to `cash_analytics/1`, `burn_rate_analytics/1`,
  `runway_analytics/1`, or `net_flow_analytics/1`.
  """
  def window(opts \\ []) do
    now =
      opts
      |> Keyword.get(:now, DateTime.utc_now())
      |> DateTime.truncate(:second)

    today = DateTime.to_date(now)
    report_currency = Config.report_currency()
    burn_window_days = Config.runway_window_days()
    history_days = Keyword.get(opts, :history_days, @default_history_days)
    step_days = Keyword.get(opts, :step_days) || resolve_step_days(history_days)

    load_start_date = Date.add(today, -(history_days + burn_window_days))
    load_start = DateTime.new!(load_start_date, ~T[00:00:00], "Etc/UTC")

    accounts = Query.list_accounts()
    transactions = transactions_since(load_start)
    exchange_rates = load_exchange_rates(report_currency, accounts, transactions)

    # Bank-balance reconstruction must use every cash-affecting transaction
    # (including transfers); burn/runway/net only use runway-relevant ones.
    cash_transactions = Enum.filter(transactions, & &1.affects_cash_balance)
    runway_transactions = Enum.filter(transactions, & &1.affects_runway)

    %{
      now: now,
      today: today,
      currency: report_currency,
      burn_window_days: burn_window_days,
      history_days: history_days,
      step_days: step_days,
      account_count: length(accounts),
      dates: build_dates(today, history_days, step_days),
      current_balance: sum_account_balances(accounts, report_currency, exchange_rates),
      daily_cash_flow: build_daily_net_flow(cash_transactions, report_currency, exchange_rates),
      daily_net_flow: build_daily_net_flow(runway_transactions, report_currency, exchange_rates),
      daily_revenue: build_daily_directional(runway_transactions, "credit", report_currency, exchange_rates),
      daily_expense: build_daily_directional(runway_transactions, "debit", report_currency, exchange_rates)
    }
  end

  @doc """
  Total available cash across accounts (report currency), reconstructed backwards
  from the current balance using every cash-affecting transaction (transfers
  included), so the curve tracks the real bank balance rather than only
  runway-relevant movement.
  """
  def cash_analytics(window) do
    window
    |> balance_series()
    |> to_analytics(window)
  end

  @doc """
  Monthly burn estimate: the negative net cash flow over a trailing window ending
  at each bucket, normalized to a 30-day month. Zero when cash flow is positive.
  """
  def burn_rate_analytics(window) do
    window
    |> burn_series()
    |> to_analytics(window)
  end

  @doc """
  Runway in months at each bucket: reconstructed balance divided by the smoothed
  burn. `value` entries are `nil` where there is no measurable burn.
  """
  def runway_analytics(window) do
    balance_series = balance_series(window)
    burn_series = burn_series(window)

    balance_series
    |> build_runway_series(burn_series)
    |> to_analytics(window)
  end

  @doc """
  Net cash flow that occurred *within* each bucket period (credits minus debits),
  rather than a trailing window.
  """
  def net_flow_analytics(window) do
    window
    |> period_net_series()
    |> to_analytics(window)
  end

  @doc """
  Per-calendar-month income and expenses in absolute terms. Returns a map
  with `dates` anchored to the last day of each calendar month, `income`
  and `expense` value lists in `currency`, the latest month's totals, and
  the income trend versus the prior month.
  """
  def cash_flow_analytics(window) do
    months = build_calendar_months(window.today, window.history_days)
    income_series = build_calendar_month_series(months, window.daily_revenue)
    expense_series = build_calendar_month_series(months, window.daily_expense)

    %{
      currency: window.currency,
      dates: Enum.map(income_series, & &1.date),
      income: Enum.map(income_series, & &1.value),
      expense: Enum.map(expense_series, & &1.value),
      income_value: income_series |> List.last(%{}) |> Map.get(:value),
      expense_value: expense_series |> List.last(%{}) |> Map.get(:value),
      income_trend: series_trend(income_series)
    }
  end

  defp balance_series(window) do
    build_balance_series(window.dates, window.current_balance, window.daily_cash_flow, window.today)
  end

  defp burn_series(window) do
    build_burn_series(window.dates, window.daily_net_flow, window.burn_window_days)
  end

  defp period_net_series(window) do
    build_period_net_series(window.dates, window.daily_net_flow, window.step_days)
  end

  defp to_analytics(series, window) do
    %{
      currency: window.currency,
      dates: Enum.map(series, & &1.date),
      values: Enum.map(series, & &1.value),
      value: series |> List.last(%{}) |> Map.get(:value),
      trend: series_trend(series)
    }
  end

  # Percentage change between the latest bucket and the bucket roughly a month
  # earlier. `nil` when either point is missing or the reference value is zero.
  defp series_trend(series) do
    with %{date: latest_date, value: %Decimal{} = latest} <- List.last(series),
         %{value: %Decimal{} = prior} <- trend_reference(series, latest_date),
         false <- Decimal.equal?(prior, @zero) do
      latest
      |> Decimal.sub(prior)
      |> Decimal.div(Decimal.abs(prior))
      |> Decimal.mult(Decimal.new("100"))
      |> Decimal.to_float()
    else
      _ -> nil
    end
  end

  defp trend_reference(series, latest_date) do
    target = Date.add(latest_date, -@trend_window_days)

    series
    |> Enum.filter(fn %{date: date} -> Date.compare(date, target) != :gt end)
    |> case do
      [] -> List.first(series)
      candidates -> List.last(candidates)
    end
  end

  defp transactions_since(started_at) do
    # The `affects_cash_balance` / `affects_runway` flags already encode whether a
    # transaction counts (providers derive them from status — e.g. Qonto only
    # flags "completed" rows, Mercury flags "sent" ones). Gating on a literal
    # status here would wrongly drop Mercury's "sent" transactions.
    Transaction
    |> where([transaction], transaction.affects_cash_balance == true or transaction.affects_runway == true)
    |> where(
      [transaction],
      fragment("coalesce(?, ?, ?)", transaction.settled_at, transaction.booked_at, transaction.provider_updated_at) >=
        ^started_at
    )
    |> Repo.all()
  end

  defp load_exchange_rates(report_currency, accounts, transactions) do
    currencies =
      accounts
      |> Enum.flat_map(fn account ->
        [account.balance_currency, account.available_balance_currency, account.currency]
      end)
      |> Kernel.++(Enum.map(transactions, & &1.amount_currency))
      |> Enum.map(&Amounts.normalize_currency/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.reject(&(&1 == "EUR"))

    case ExchangeRates.latest_rates(currencies) do
      {:ok, exchange_rates} -> Map.put(exchange_rates, :report_currency, report_currency)
      {:error, _reason} -> %{published_on: nil, rates: %{}, report_currency: report_currency}
    end
  end

  defp sum_account_balances(accounts, report_currency, exchange_rates) do
    Enum.reduce(accounts, @zero, fn account, total ->
      value = account.available_balance_value || account.balance_value
      currency = account.available_balance_currency || account.balance_currency

      case convert(value, currency, report_currency, exchange_rates) do
        {:ok, amount} -> Decimal.add(total, amount)
        :skip -> total
      end
    end)
  end

  defp build_daily_net_flow(transactions, report_currency, exchange_rates) do
    Enum.reduce(transactions, %{}, fn transaction, acc ->
      case convert(transaction.amount_value, transaction.amount_currency, report_currency, exchange_rates) do
        {:ok, amount} ->
          signed =
            case transaction.direction do
              "credit" -> amount
              "debit" -> Decimal.negate(amount)
              _other -> @zero
            end

          date = transaction |> Transaction.occurred_at() |> DateTime.to_date()
          Map.update(acc, date, signed, &Decimal.add(&1, signed))

        :skip ->
          acc
      end
    end)
  end

  defp build_daily_directional(transactions, direction, report_currency, exchange_rates) do
    transactions
    |> Enum.filter(&(&1.direction == direction))
    |> Enum.reduce(%{}, fn transaction, acc ->
      case convert(transaction.amount_value, transaction.amount_currency, report_currency, exchange_rates) do
        {:ok, amount} ->
          date = transaction |> Transaction.occurred_at() |> DateTime.to_date()
          Map.update(acc, date, amount, &Decimal.add(&1, amount))

        :skip ->
          acc
      end
    end)
  end

  # Calendar-month bucket anchors (last day of each month) covering roughly
  # `history_days` of past months. Always includes the current month.
  defp build_calendar_months(today, history_days) do
    months = max(1, div(history_days, 30))
    {start_year, start_month} = shift_month(today.year, today.month, -(months - 1))

    Stream.iterate({start_year, start_month}, fn {year, month} -> shift_month(year, month, 1) end)
    |> Enum.take(months)
    |> Enum.map(fn {year, month} -> last_day_of_month(year, month) end)
  end

  defp build_calendar_month_series(month_dates, daily_amounts) do
    Enum.map(month_dates, fn date ->
      first_day = %{date | day: 1}
      %{date: date, value: sum_net_flow_in(daily_amounts, first_day, date)}
    end)
  end

  defp shift_month(year, month, delta) do
    total = year * 12 + (month - 1) + delta
    {div(total, 12), rem(total, 12) + 1}
  end

  defp last_day_of_month(year, month) do
    Date.new!(year, month, Date.days_in_month(Date.new!(year, month, 1)))
  end

  defp resolve_step_days(history_days) when history_days > @monthly_step_threshold_days, do: @monthly_step_days
  defp resolve_step_days(_history_days), do: @weekly_step_days

  # Even buckets anchored at `today`, stepping backwards so the most recent
  # bucket always ends exactly on today (no short trailing period).
  defp build_dates(today, history_days, step_days) do
    steps = div(history_days, step_days)

    0..steps
    |> Enum.map(fn i -> Date.add(today, -i * step_days) end)
    |> Enum.uniq()
    |> Enum.sort(Date)
  end

  defp build_balance_series(dates, current_balance, daily_net_flow, today) do
    {entries, _, _} =
      dates
      |> Enum.reverse()
      |> Enum.reduce({[], today, current_balance}, fn date, {acc, next_date, next_balance} ->
        net = sum_net_flow_in(daily_net_flow, Date.add(date, 1), next_date)
        balance = Decimal.sub(next_balance, net)
        {[%{date: date, value: balance} | acc], date, balance}
      end)

    entries
  end

  defp build_burn_series(dates, daily_net_flow, burn_window_days) do
    months = burn_window_days |> Decimal.new() |> Decimal.div(@thirty)
    first_flow_date = daily_net_flow |> Map.keys() |> Enum.min(Date, fn -> nil end)

    Enum.map(dates, fn date ->
      window_start = Date.add(date, -burn_window_days + 1)
      %{date: date, value: burn_value(daily_net_flow, window_start, date, first_flow_date, months)}
    end)
  end

  # `nil` when we have runway data but the trailing window starts before our
  # first transaction: only part of the window is covered, so dividing the net
  # by the full month count would understate burn and balloon the runway (the
  # bogus "110 months" early buckets). With no runway data at all, or a fully
  # covered window, it is the negated net normalized to a 30-day month (`@zero`
  # when the window is cash-positive).
  defp burn_value(daily_net_flow, window_start, date, first_flow_date, months) do
    if !(not is_nil(first_flow_date) and Date.after?(first_flow_date, window_start)) do
      net = sum_net_flow_in(daily_net_flow, window_start, date)

      case Decimal.compare(net, @zero) do
        :lt -> net |> Decimal.negate() |> Decimal.div(months)
        _ -> @zero
      end
    end
  end

  # Net cash flow that occurred *within* each bucket (between consecutive bucket
  # boundaries), rather than a trailing window. For the first bucket we look back
  # one step so the period length stays consistent.
  defp build_period_net_series(dates, daily_net_flow, step_days) do
    dates
    |> Enum.with_index()
    |> Enum.map(fn {date, index} ->
      previous_date =
        case index do
          0 -> Date.add(date, -step_days)
          _ -> Enum.at(dates, index - 1)
        end

      net = sum_net_flow_in(daily_net_flow, Date.add(previous_date, 1), date)
      %{date: date, value: net}
    end)
  end

  defp build_runway_series(balance_series, burn_series) do
    balance_map = Map.new(balance_series, &{&1.date, &1.value})

    Enum.map(burn_series, fn %{date: date, value: burn} ->
      balance = Map.fetch!(balance_map, date)
      %{date: date, value: runway_value(balance, burn)}
    end)
  end

  defp runway_value(_balance, nil), do: nil

  defp runway_value(balance, %Decimal{} = burn) do
    case Decimal.compare(burn, @zero) do
      :gt -> Decimal.div(balance, burn)
      _ -> nil
    end
  end

  defp sum_net_flow_in(daily_net_flow, from_date, to_date) do
    if Date.after?(from_date, to_date) do
      @zero
    else
      Enum.reduce(daily_net_flow, @zero, fn {date, value}, acc ->
        if Date.compare(date, from_date) != :lt and Date.compare(date, to_date) != :gt do
          Decimal.add(acc, value)
        else
          acc
        end
      end)
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
end
