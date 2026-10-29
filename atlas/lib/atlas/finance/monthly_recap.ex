defmodule Atlas.Finance.MonthlyRecap do
  @moduledoc false

  alias Atlas.Accounts.Amounts
  alias Atlas.Finance
  alias Atlas.Finance.Transaction

  @zero Decimal.new("0")

  def build(%{start_at: %DateTime{} = start_at, end_at: %DateTime{} = end_at}) do
    overview = Finance.overview()
    currency = overview.currency

    expense_history =
      Finance.expense_history(
        ending_on: end_at |> DateTime.add(-1, :second) |> DateTime.to_date(),
        months: 3,
        currency: currency
      )

    transactions =
      Finance.list_transactions(
        date_from: start_at,
        date_to: DateTime.add(end_at, -1, :second),
        currency: currency,
        limit: 100
      )

    current_costs = List.last(expense_history.months)
    previous_costs = Enum.at(expense_history.months, -2)
    metrics = metrics(overview, current_costs, previous_costs, transactions)

    %{
      "kind" => "monthly_finance_recap",
      "headline" => headline(start_at, metrics),
      "intro" => intro(metrics),
      "sections" => sections(metrics)
    }
  end

  defp metrics(overview, current_costs, previous_costs, transactions) do
    operating_costs = current_costs.total_amount_value
    cash_inflow = cash_inflow(transactions)

    %{
      overview: overview,
      currency: overview.currency,
      operating_costs: operating_costs,
      previous_operating_costs: previous_costs && previous_costs.total_amount_value,
      cash_inflow: cash_inflow,
      net_operating_cash_flow: Decimal.sub(cash_inflow, operating_costs),
      categories: Map.get(current_costs, :categories, []) |> Enum.take(3),
      cost_data_complete?: current_costs.complete?,
      cost_exclusions: Map.get(current_costs, :exclusions, %{}),
      largest_transactions: largest_transactions(transactions)
    }
  end

  defp cash_inflow(transactions) do
    transactions
    |> Enum.filter(&(&1.direction == "credit" and &1.affects_runway))
    |> Enum.reduce(@zero, fn transaction, total -> Decimal.add(total, transaction.amount_value) end)
  end

  defp largest_transactions(transactions) do
    transactions
    |> Enum.filter(&(&1.affects_runway and match?(%Decimal{}, &1.amount_value)))
    |> Enum.sort_by(& &1.amount_value, {:desc, Decimal})
    |> Enum.take(5)
  end

  defp headline(start_at, metrics) do
    month = start_at |> DateTime.to_date() |> Calendar.strftime("%B %Y")
    flow = metrics.net_operating_cash_flow

    cash_flow_text =
      if Decimal.negative?(flow) do
        "operating cash outflow of #{amount(Decimal.abs(flow), metrics.currency)}"
      else
        "operating cash inflow of #{amount(flow, metrics.currency)}"
      end

    "#{month}: #{cash_flow_text}; closing cash is " <>
      "#{amount(metrics.overview.available_cash_value, metrics.currency)} with #{runway(metrics.overview.runway_months)} of runway."
  end

  defp intro(metrics) do
    "Cash received was #{amount(metrics.cash_inflow, metrics.currency)} and operating costs were " <>
      "#{amount(metrics.operating_costs, metrics.currency)}, resulting in #{cash_flow_label(metrics.net_operating_cash_flow, metrics.currency)}."
  end

  defp sections(metrics) do
    [
      %{"heading" => "Monthly snapshot", "text" => snapshot(metrics)},
      %{"heading" => "Cost breakdown", "text" => cost_breakdown(metrics)},
      %{"heading" => "Largest cash movements", "text" => largest_cash_movements(metrics)},
      %{"heading" => "Key insights", "text" => key_insights(metrics)},
      %{"heading" => "Recommended focus", "text" => recommendations(metrics)},
      %{"heading" => "Alerts and data quality", "text" => alerts(metrics)}
    ]
  end

  defp snapshot(metrics) do
    [
      "• *Cash received:* #{amount(metrics.cash_inflow, metrics.currency)}",
      "• *Operating costs:* #{amount(metrics.operating_costs, metrics.currency)}#{cost_change(metrics)}",
      "• *Net operating cash flow:* #{cash_flow_label(metrics.net_operating_cash_flow, metrics.currency)}",
      "• *Closing cash:* #{amount(metrics.overview.available_cash_value, metrics.currency)}",
      "• *Estimated runway:* #{runway(metrics.overview.runway_months)}"
    ]
    |> Enum.join("\n")
  end

  defp cost_breakdown(%{categories: []}) do
    "No categorized operating costs were available for the reporting month."
  end

  defp cost_breakdown(metrics) do
    metrics.categories
    |> Enum.map_join("\n", fn category ->
      share = percentage(category.total_amount_value, metrics.operating_costs)

      "• *#{category.name}:* #{amount(category.total_amount_value, metrics.currency)}" <>
        " (#{share} of operating costs, #{category.transaction_count} transactions)"
    end)
  end

  defp largest_cash_movements(%{largest_transactions: []}) do
    "No runway-relevant cash movements were recorded for the reporting month."
  end

  defp largest_cash_movements(metrics) do
    metrics.largest_transactions
    |> Enum.map_join("\n", fn transaction ->
      direction = if transaction.direction == "credit", do: "In", else: "Out"

      label =
        transaction.counterparty_name || transaction.description || transaction.reference || "Unlabelled transaction"

      date = transaction |> Transaction.occurred_at() |> DateTime.to_date() |> Date.to_iso8601()

      "• *#{direction} #{amount(transaction.amount_value, metrics.currency)}:* #{label} on #{date}"
    end)
  end

  defp key_insights(metrics) do
    [cash_flow_insight(metrics), cost_change_insight(metrics), category_insight(metrics), runway_insight(metrics)]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join("\n", &"• #{&1}")
  end

  defp cash_flow_insight(metrics) do
    "Cash received of #{amount(metrics.cash_inflow, metrics.currency)} against operating costs of " <>
      "#{amount(metrics.operating_costs, metrics.currency)} produced #{cash_flow_label(metrics.net_operating_cash_flow, metrics.currency)}."
  end

  defp cost_change_insight(%{previous_operating_costs: nil}), do: nil

  defp cost_change_insight(metrics) do
    case change(metrics.operating_costs, metrics.previous_operating_costs) do
      nil ->
        "Operating costs had no comparable prior-month baseline."

      %{direction: direction, percentage: percentage, difference: difference} ->
        "Operating costs #{direction} by #{percentage} (#{amount(difference, metrics.currency)}) versus the previous month."
    end
  end

  defp category_insight(%{categories: []}), do: nil

  defp category_insight(metrics) do
    category = List.first(metrics.categories)

    "#{category.name} was the largest cost area at #{amount(category.total_amount_value, metrics.currency)}, " <>
      "representing #{percentage(category.total_amount_value, metrics.operating_costs)} of operating costs."
  end

  defp runway_insight(metrics) do
    "The month closed with #{amount(metrics.overview.available_cash_value, metrics.currency)} in available cash and " <>
      "#{runway(metrics.overview.runway_months)} of estimated runway."
  end

  defp recommendations(metrics) do
    [cash_flow_recommendation(metrics), cost_recommendation(metrics), category_recommendation(metrics)]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join("\n", &"• #{&1}")
  end

  defp cash_flow_recommendation(metrics) do
    if Decimal.negative?(metrics.net_operating_cash_flow) do
      "Confirm the timing and collectability of the largest expected cash receipts before the next payroll and vendor-payment cycle."
    else
      "Keep the current cash-collection cadence while reviewing the largest recurring operating costs."
    end
  end

  defp cost_recommendation(metrics) do
    case change(metrics.operating_costs, metrics.previous_operating_costs) do
      %{direction: "increased", percentage_value: percentage_value} ->
        if Decimal.compare(percentage_value, Decimal.new("10")) in [:eq, :gt] do
          "Review the month-over-month cost increase and confirm which commitments are recurring versus one-time."
        end

      _other ->
        nil
    end
  end

  defp category_recommendation(%{categories: []}), do: nil

  defp category_recommendation(metrics) do
    category = List.first(metrics.categories)

    "Review #{category.name} spending, the largest operating-cost area this month, for upcoming renewal or right-sizing decisions."
  end

  defp alerts(metrics) do
    [
      negative_cash_flow_alert(metrics),
      runway_alert(metrics),
      incomplete_cost_data_alert(metrics),
      unconverted_currency_alert(metrics)
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> "No finance or data-quality alerts were detected in the reporting window."
      alerts -> Enum.map_join(alerts, "\n", &"• #{&1}")
    end
  end

  defp negative_cash_flow_alert(metrics) do
    if Decimal.negative?(metrics.net_operating_cash_flow) do
      "*Negative operating cash flow:* #{cash_flow_label(metrics.net_operating_cash_flow, metrics.currency)} for the month."
    end
  end

  defp runway_alert(%{overview: %{runway_months: %Decimal{} = runway}}) do
    cond do
      Decimal.compare(runway, Decimal.new("6")) == :lt ->
        "*Runway:* estimated runway is below six months at #{runway(runway)}."

      Decimal.compare(runway, Decimal.new("12")) == :lt ->
        "*Runway:* estimated runway is below twelve months at #{runway(runway)}."

      true ->
        nil
    end
  end

  defp runway_alert(_metrics), do: nil

  defp incomplete_cost_data_alert(%{cost_data_complete?: true}), do: nil

  defp incomplete_cost_data_alert(_metrics) do
    "*Cost data is incomplete:* one or more operating-cost transactions could not be converted to the report currency."
  end

  defp unconverted_currency_alert(metrics) do
    currencies = Map.get(metrics.cost_exclusions, :unconverted_currencies, [])

    case currencies do
      [] -> nil
      currencies -> "*Unconverted currencies:* #{Enum.join(currencies, ", ")}."
    end
  end

  defp cost_change(metrics) do
    case change(metrics.operating_costs, metrics.previous_operating_costs) do
      nil -> ""
      %{direction: direction, percentage: percentage} -> " (#{direction} #{percentage} month over month)"
    end
  end

  defp change(_current, nil), do: nil

  defp change(current, previous) do
    if !Decimal.equal?(previous, @zero) do
      difference = Decimal.sub(current, previous)
      direction = if Decimal.negative?(difference), do: "decreased", else: "increased"

      %{
        direction: direction,
        difference: Decimal.abs(difference),
        percentage: percentage(Decimal.abs(difference), previous),
        percentage_value:
          difference
          |> Decimal.abs()
          |> Decimal.mult(Decimal.new("100"))
          |> Decimal.div(previous)
      }
    end
  end

  defp cash_flow_label(value, currency) do
    if Decimal.negative?(value), do: "-#{amount(Decimal.abs(value), currency)}", else: amount(value, currency)
  end

  defp amount(value, currency), do: Amounts.format(value || @zero, currency)
  defp runway(nil), do: "not available"

  defp runway(%Decimal{} = value) do
    "#{value |> Decimal.round(1) |> Decimal.to_string(:normal)} months"
  end

  defp percentage(_value, total) when total == nil, do: "not available"

  defp percentage(value, total) do
    if Decimal.equal?(total, @zero) do
      "not available"
    else
      value
      |> Decimal.mult(Decimal.new("100"))
      |> Decimal.div(total)
      |> Decimal.round(1)
      |> Decimal.to_string(:normal)
      |> Kernel.<>("%")
    end
  end
end
