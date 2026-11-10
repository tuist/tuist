defmodule Pulse.LogQL.Quantile do
  @moduledoc false
  alias Pulse.PromQL.Number

  def calculate(_, []), do: :nan
  def calculate(:nan, _), do: :nan
  def calculate(:negative_infinity, _), do: :negative_infinity
  def calculate(:infinity, _), do: :infinity
  def calculate(q, _) when is_number(q) and q < 0, do: :negative_infinity
  def calculate(q, _) when is_number(q) and q > 1, do: :infinity

  def calculate(q, values) when is_number(q) do
    sorted = Enum.sort(values, &before?/2)
    rank = q * 1.0 * (length(sorted) - 1)
    lower = max(0, trunc(Float.floor(rank)))
    upper = min(length(sorted) - 1, lower + 1)
    weight = rank - Float.floor(rank)
    Number.add(Number.multiply(Enum.at(sorted, lower), 1 - weight), Number.multiply(Enum.at(sorted, upper), weight))
  end

  defp before?(:nan, _), do: true
  defp before?(_, :nan), do: false
  defp before?(a, b), do: Number.compare("<=", a, b)
end
