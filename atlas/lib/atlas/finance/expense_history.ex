defmodule Atlas.Finance.ExpenseHistory do
  @moduledoc false

  alias Atlas.Finance.ExpenseReconciliation

  @default_months 3
  @max_months 12

  def build(opts \\ []) do
    ending_on = Keyword.get(opts, :ending_on, Date.utc_today())
    months = opts |> Keyword.get(:months, @default_months) |> normalize_months()
    currency = Keyword.get(opts, :currency)

    months = monthly_periods(ending_on, months)

    reports =
      Enum.map(months, fn %{date_from: date_from, date_to: date_to} = period ->
        reconciliation =
          ExpenseReconciliation.build(
            date_from: start_of_day(date_from),
            date_to: end_of_day(date_to),
            currency: currency
          )

        %{
          period: period,
          currency: reconciliation.currency,
          total_amount_value: reconciliation.total_amount_value,
          included_transaction_count: reconciliation.included_transaction_count,
          matching_debit_transaction_count: reconciliation.matching_debit_transaction_count,
          complete?: reconciliation.complete?,
          categories: reconciliation.categories,
          exclusions: reconciliation.exclusions
        }
      end)

    %{currency: reports |> List.first() |> Map.get(:currency, currency), months: reports}
  end

  defp monthly_periods(ending_on, months) do
    current_month = Date.beginning_of_month(ending_on)

    Range.new(months - 1, 0, -1)
    |> Enum.map(&shift_months(current_month, -&1))
    |> Enum.map(fn month_start ->
      date_to =
        if month_start == current_month do
          ending_on
        else
          Date.end_of_month(month_start)
        end

      %{date_from: month_start, date_to: date_to, partial?: date_to != Date.end_of_month(month_start)}
    end)
  end

  defp shift_months(%Date{year: year, month: month}, offset) do
    month_index = year * 12 + month - 1 + offset
    Date.new!(div(month_index, 12), rem(month_index, 12) + 1, 1)
  end

  defp normalize_months(value) when is_integer(value) and value > 0, do: min(value, @max_months)
  defp normalize_months(_value), do: @default_months

  defp start_of_day(date), do: DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
  defp end_of_day(date), do: DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
end
