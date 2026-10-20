defmodule Atlas.Accounts.ExchangeRatesTest do
  use ExUnit.Case, async: true

  alias Atlas.Accounts.ExchangeRates

  test "normalizes Forex latest rates for selected currencies" do
    assert {:ok, rates} =
             ExchangeRates.latest_rates(["usd", "USD"],
               feed_fn: {__MODULE__, :latest_rates_feed, []}
             )

    assert rates.published_on == ~D[2026-04-30]
    assert Map.keys(rates.rates) == ["USD"]
    assert Decimal.equal?(rates.rates["USD"], Decimal.new("1.1702"))
  end

  test "does not call Forex when no currencies are needed" do
    assert ExchangeRates.latest_rates([]) == {:ok, %{published_on: nil, rates: %{}}}
  end

  def latest_rates_feed do
    {:ok,
     [
       %{
         time: ~D[2026-04-30],
         rates: [
           %{currency: "USD", rate: "1.1702"},
           %{currency: "GBP", rate: "0.8567"}
         ]
       }
     ]}
  end
end
