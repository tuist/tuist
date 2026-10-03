defmodule Atlas.Accounts.Snapshot do
  @moduledoc false

  alias Atlas.Accounts.Amounts
  alias Atlas.Accounts.ContractValue

  @twelve Decimal.new("12")
  @zero Decimal.new("0")
  @days_per_month Decimal.new("30.4375")

  def build(accounts, latest_term_events, exchange_rates) when is_list(accounts) do
    exchange_rates = exchange_rates || %{published_on: nil, rates: %{}}

    {monthly_revenue_eur, estimated_arr_eur, renewal_base_count} =
      accounts
      |> Enum.filter(&include_account?/1)
      |> Enum.reduce({@zero, @zero, 0}, fn account, {monthly_total, arr_total, count} ->
        case revenue_for_account(account, Map.get(latest_term_events, account.id), exchange_rates) do
          {:ok, monthly_value_eur, annual_value_eur} ->
            {
              Decimal.add(monthly_total, monthly_value_eur),
              Decimal.add(arr_total, annual_value_eur),
              count + 1
            }

          :skip ->
            {monthly_total, arr_total, count}
        end
      end)

    %{
      monthly_revenue_eur: Decimal.round(monthly_revenue_eur, 2),
      estimated_arr_eur: Decimal.round(estimated_arr_eur, 2),
      renewal_base_count: renewal_base_count,
      usd_to_eur_rate: usd_to_eur_rate(exchange_rates),
      published_on: exchange_rates.published_on
    }
  end

  def note(_snapshot),
    do:
      "MRR Equivalent normalizes each renewable customer contract by term length, preferring the term that is active today and otherwise the nearest signed term. Estimated ARR annualizes that normalized monthly value and assumes those contracts renew."

  defp include_account?(account) do
    account.segment == :customer and not churned?(account) and not not_account?(account)
  end

  defp churned?(%{status: "churned"}), do: true
  defp churned?(_account), do: false

  defp not_account?(%{not_an_account_at: %DateTime{}}), do: true
  defp not_account?(_account), do: false

  defp revenue_for_account(account, latest_term_event, exchange_rates) do
    revenue_source = revenue_source(account)

    with {:ok, value} <- billable_value(revenue_source.value),
         {:ok, value_eur} <- convert_to_eur(value, revenue_source.currency, exchange_rates),
         {:ok, term_months} <- term_months(account, latest_term_event, revenue_source) do
      monthly_value_eur = Decimal.div(value_eur, term_months)
      annual_value_eur = Decimal.mult(monthly_value_eur, @twelve)
      {:ok, monthly_value_eur, annual_value_eur}
    else
      _error -> :skip
    end
  end

  defp revenue_source(account) do
    case ContractValue.source(account) do
      %{source: :account, value: value, currency: currency} ->
        %{
          source: :account,
          value: value,
          currency: currency
        }

      %{source: :term, value: value, currency: currency, term: term} ->
        %{
          source: :term,
          value: value,
          currency: currency,
          payment: term.payment,
          start_date: term.start_date,
          end_date: term.end_date
        }
    end
  end

  # A contract worth nothing carries no revenue, so it stays out of the
  # renewal base rather than padding the count with a zero.
  defp billable_value(%Decimal{} = value) do
    if Decimal.equal?(value, @zero), do: :skip, else: {:ok, value}
  end

  defp billable_value(_value), do: :skip

  defp convert_to_eur(_value, nil = _currency, _exchange_rates), do: :skip

  defp convert_to_eur(value, currency, exchange_rates) do
    normalized_currency = Amounts.normalize_currency(currency)

    case normalized_currency do
      "EUR" ->
        {:ok, value}

      currency_code ->
        case Map.get(exchange_rates.rates, currency_code) do
          %Decimal{} = rate ->
            {:ok, Decimal.div(value, rate)}

          _missing ->
            :skip
        end
    end
  end

  defp term_months(account, _latest_term_event, %{source: :term} = term) do
    months_from_term_dates(term.start_date, term.end_date) ||
      payment_months(term.payment) ||
      fallback_term_months(account)
  end

  defp term_months(account, latest_term_event, %{source: :account}) do
    metadata = Map.get(account.metadata, "current_term", %{})
    payment = metadata["payment"] || payment_from_event(latest_term_event)
    start_date = parse_date(metadata["start_date"]) || start_date_from_event(latest_term_event)
    end_date = parse_date(metadata["end_date"]) || account.next_renewal_date || end_date_from_event(latest_term_event)

    payment_months(payment) ||
      months_from_dates(start_date, end_date) ||
      fallback_term_months(account)
  end

  defp payment_from_event(nil), do: nil
  defp payment_from_event(event), do: Map.get(event.metadata, "payment")

  defp start_date_from_event(nil), do: nil
  defp start_date_from_event(event), do: DateTime.to_date(event.occurred_at)

  defp end_date_from_event(nil), do: nil
  defp end_date_from_event(event), do: parse_date(Map.get(event.metadata, "end_date"))

  defp payment_months(nil), do: nil
  defp payment_months("monthly"), do: {:ok, Decimal.new("1")}
  defp payment_months("quarterly"), do: {:ok, Decimal.new("3")}
  defp payment_months("yearly"), do: {:ok, Decimal.new("12")}
  defp payment_months("annual"), do: {:ok, Decimal.new("12")}
  defp payment_months(_payment), do: nil

  defp months_from_term_dates(%Date{} = start_date, %Date{} = end_date) do
    calendar_months_from_inclusive_dates(start_date, end_date) ||
      months_from_inclusive_dates(start_date, end_date)
  end

  defp months_from_term_dates(_start_date, _end_date), do: nil

  defp calendar_months_from_inclusive_dates(start_date, end_date) do
    exclusive_end_date = Date.add(end_date, 1)

    months = (exclusive_end_date.year - start_date.year) * 12 + exclusive_end_date.month - start_date.month

    if months > 0 and exclusive_end_date.day == start_date.day do
      {:ok, Decimal.new(months)}
    end
  end

  defp months_from_inclusive_dates(%Date{} = start_date, %Date{} = end_date) do
    case Date.compare(end_date, start_date) do
      :gt -> months_from_dates(start_date, Date.add(end_date, 1))
      _other -> nil
    end
  end

  defp months_from_dates(%Date{} = start_date, %Date{} = end_date) do
    case Date.compare(end_date, start_date) do
      :gt ->
        {:ok,
         end_date
         |> Date.diff(start_date)
         |> Decimal.new()
         |> Decimal.div(@days_per_month)}

      _other ->
        nil
    end
  end

  defp months_from_dates(_start_date, _end_date), do: nil

  defp fallback_term_months(account) do
    case account.next_renewal_date do
      %Date{} -> {:ok, Decimal.new("12")}
      _other -> nil
    end
  end

  defp usd_to_eur_rate(%{rates: %{"USD" => %Decimal{} = usd_per_eur}}) do
    Decimal.div(Decimal.new("1"), usd_per_eur) |> Decimal.round(4)
  end

  defp usd_to_eur_rate(_exchange_rates), do: nil

  defp parse_date(nil), do: nil

  defp parse_date(%Date{} = date), do: date

  defp parse_date(value) do
    case Date.from_iso8601(to_string(value)) do
      {:ok, date} -> date
      _error -> nil
    end
  end
end
