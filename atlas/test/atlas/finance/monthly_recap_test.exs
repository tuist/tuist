defmodule Atlas.Finance.MonthlyRecapTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.Finance
  alias Atlas.Finance.MonthlyRecap
  alias Atlas.Finance.Transaction

  setup :verify_on_exit!

  test "builds a leadership-ready month-end recap from reconciled finance data" do
    period = %{start_at: ~U[2026-08-01 00:00:00Z], end_at: ~U[2026-09-01 00:00:00Z]}

    stub(Finance, :overview, fn ->
      %{
        currency: "EUR",
        available_cash_value: Decimal.new("260411.58"),
        runway_months: Decimal.new("8.16")
      }
    end)

    expect(Finance, :expense_history, fn opts ->
      assert opts[:ending_on] == ~D[2026-08-31]
      assert opts[:months] == 3
      assert opts[:currency] == "EUR"

      %{
        currency: "EUR",
        months: [
          cost_month(~D[2026-06-01], Decimal.new("32000.00")),
          cost_month(~D[2026-07-01], Decimal.new("65000.00")),
          %{
            period: %{date_from: ~D[2026-08-01], date_to: ~D[2026-08-31], partial?: false},
            total_amount_value: Decimal.new("78866.49"),
            complete?: true,
            exclusions: %{unconverted_currencies: []},
            categories: [
              %{name: "Personnel", total_amount_value: Decimal.new("31491.11"), transaction_count: 4},
              %{name: "Information technology", total_amount_value: Decimal.new("27897.35"), transaction_count: 7}
            ]
          }
        ]
      }
    end)

    expect(Finance, :list_transactions, fn opts ->
      assert opts[:date_from] == period.start_at
      assert opts[:date_to] == ~U[2026-08-31 23:59:59Z]
      assert opts[:currency] == "EUR"
      assert opts[:limit] == 100

      [
        transaction("credit", "Pinterest", "34186.70", ~U[2026-08-29 12:00:00Z]),
        transaction("debit", "Vanta", "6647.67", ~U[2026-08-17 12:00:00Z]),
        transaction("debit", "BreachLock", "3700.00", ~U[2026-08-18 12:00:00Z])
      ]
    end)

    report = MonthlyRecap.build(period)

    assert report["kind"] == "monthly_finance_recap"
    assert report["headline"] =~ "August 2026"
    assert report["headline"] =~ "EUR 260,411.58"
    assert report["intro"] =~ "EUR 34,186.70"
    assert report["intro"] =~ "EUR 78,866.49"

    sections = Map.new(report["sections"], &{&1["heading"], &1["text"]})

    assert sections["Monthly snapshot"] =~ "8.2 months"
    assert sections["Cost breakdown"] =~ "Personnel"
    assert sections["Largest cash movements"] =~ "Pinterest"
    assert sections["Key insights"] =~ "increased by 21.3%"
    assert sections["Recommended focus"] =~ "month-over-month cost increase"
    assert sections["Alerts and data quality"] =~ "Negative operating cash flow"
  end

  defp cost_month(date_from, total) do
    %{
      period: %{date_from: date_from, date_to: Date.end_of_month(date_from), partial?: false},
      total_amount_value: total,
      complete?: true,
      exclusions: %{unconverted_currencies: []},
      categories: []
    }
  end

  defp transaction(direction, counterparty_name, amount_value, settled_at) do
    %Transaction{
      direction: direction,
      counterparty_name: counterparty_name,
      amount_value: Decimal.new(amount_value),
      amount_currency: "EUR",
      affects_runway: true,
      settled_at: settled_at
    }
  end
end
