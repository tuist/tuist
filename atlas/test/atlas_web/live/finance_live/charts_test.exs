defmodule AtlasWeb.FinanceLive.ChartsTest do
  use ExUnit.Case, async: true

  alias AtlasWeb.FinanceLive.Charts

  describe "signed_bar_series/3" do
    test "colors net inflow green, outflow red, and scales the value" do
      dates = [~D[2025-12-29], ~D[2026-01-29], ~D[2026-02-28]]
      values = [Decimal.new("73640"), Decimal.new("-30700"), Decimal.new("0")]

      assert [
               %{value: ["2025-12-29", 73.64], itemStyle: %{color: "var:noora-chart-tertiary"}},
               %{value: ["2026-01-29", -30.7], itemStyle: %{color: "var:noora-chart-destructive"}},
               %{value: ["2026-02-28", +0.0], itemStyle: %{color: "var:noora-chart-tertiary"}}
             ] = Charts.signed_bar_series(dates, values, {1000, "K"})
    end
  end

  describe "monthly spend series" do
    test "fills the selected monthly period instead of only months with spend" do
      period = {~U[2026-05-15 00:00:00Z], ~U[2026-08-20 23:59:59Z]}

      monthly_spend = [
        %{date: ~D[2026-05-01], amount_value: Decimal.new("4200")},
        %{date: ~D[2026-08-01], amount_value: Decimal.new("1800")}
      ]

      assert Charts.monthly_series_dates(monthly_spend, period) == [
               "2026-05-01",
               "2026-06-01",
               "2026-07-01",
               "2026-08-01"
             ]

      assert Charts.scaled_monthly_series(monthly_spend, period, {1000, "K"}) == [
               ["2026-05-01", 4.2],
               ["2026-06-01", +0.0],
               ["2026-07-01", +0.0],
               ["2026-08-01", 1.8]
             ]
    end

    test "keeps an empty chart empty when there is no spend" do
      period = {~U[2026-05-15 00:00:00Z], ~U[2026-08-20 23:59:59Z]}

      assert Charts.monthly_series_dates([], period) == []
      assert Charts.scaled_monthly_series([], period, {1000, "K"}) == []
    end
  end
end
