defmodule Atlas.Native.FinanceOverview do
  @moduledoc false

  alias Atlas.Finance.Runway

  def get do
    window = Runway.window(history_days: 180)
    available? = window.account_count > 0 and window.excluded_currencies == []

    %{
      currency: window.currency,
      as_of: Date.to_iso8601(window.today),
      account_count: window.account_count,
      fx_published_on: if(window.fx_published_on, do: Date.to_iso8601(window.fx_published_on)),
      excluded_currencies: window.excluded_currencies,
      available_cash: if(available?, do: string(Runway.cash_analytics(window).value)),
      monthly_burn: if(available?, do: string(Runway.burn_rate_analytics(window).value)),
      runway_months: if(available?, do: string(Runway.runway_analytics(window).value)),
      months: if(available?, do: months(window), else: [])
    }
  end

  defp months(window) do
    flow = Runway.cash_flow_analytics(window)

    [flow.dates, flow.income, flow.expense]
    |> Enum.zip()
    |> Enum.map(fn {date, income, expense} ->
      %{month: date |> Date.to_iso8601() |> String.slice(0, 7), income: string(income), expense: string(expense)}
    end)
  end

  defp string(nil), do: nil
  defp string(value), do: Decimal.to_string(value, :normal)
end
