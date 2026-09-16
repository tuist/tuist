defmodule Atlas.Accounts.ExchangeRates do
  @moduledoc false

  def latest_rates(currencies, opts \\ [])

  def latest_rates([], _opts), do: {:ok, %{published_on: nil, rates: %{}}}

  def latest_rates(currencies, opts) when is_list(currencies) do
    currencies =
      currencies
      |> Enum.map(&String.upcase/1)
      |> Enum.uniq()
      |> Enum.sort()

    opts =
      opts
      |> Keyword.put(:keys, :strings)
      |> Keyword.put(:symbols, currencies)
      |> Keyword.put_new(:use_cache, false)

    case Forex.latest_rates(opts) do
      {:ok, %Forex{date: published_on, rates: rates}} ->
        {:ok, %{published_on: published_on, rates: rates}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
