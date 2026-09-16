defmodule Atlas.TestSupport.ExchangeRatesClient do
  @moduledoc false

  def latest_rates(currencies, _opts \\ []) do
    rates =
      currencies
      |> Enum.map(&String.upcase/1)
      |> Enum.uniq()
      |> Map.new(&{&1, Decimal.new("1.1702")})

    {:ok, %{published_on: ~D[2026-04-30], rates: rates}}
  end
end
