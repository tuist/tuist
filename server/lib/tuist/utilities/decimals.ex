defmodule Tuist.Utilities.Decimals do
  @moduledoc """
  Decimal helpers for analytics scatter/axis values coming out of ClickHouse,
  where a column may arrive as nil, a Decimal, a float, or an integer
  depending on the fragment.
  """

  @doc """
  Returns `value` as a `Decimal` rounded to one fractional digit, treating
  `nil` as zero. Accepts floats, integers, and existing `Decimal` values so
  callers can pass ClickHouse results directly without guarding on the type.
  """
  def to_rounded(nil), do: Decimal.new(0)
  def to_rounded(%Decimal{} = value), do: Decimal.round(value, 1)
  def to_rounded(value) when is_float(value), do: value |> Decimal.from_float() |> Decimal.round(1)
  def to_rounded(value) when is_integer(value), do: value |> Decimal.new() |> Decimal.round(1)
end
