defmodule Tuist.Kubernetes.Quantity do
  @moduledoc """
  Reads a Kubernetes resource quantity in whole units, at `scale` units per
  unit of the quantity: bytes for a memory or storage quantity, millicores for
  a CPU one read at a thousand. The API keeps a quantity in the form it was
  written, so every form is read: a binary suffix (`Ki` to `Ei`), a decimal one
  (`n` to `E`) or an exponent (`e3`). Rounded down; `nil` when unreadable.
  """

  @binary_suffixes %{
    "Ki" => 1024,
    "Mi" => 1024 ** 2,
    "Gi" => 1024 ** 3,
    "Ti" => 1024 ** 4,
    "Pi" => 1024 ** 5,
    "Ei" => 1024 ** 6
  }
  @decimal_exponents %{
    "n" => -9,
    "u" => -6,
    "m" => -3,
    "" => 0,
    "k" => 3,
    "M" => 6,
    "G" => 9,
    "T" => 12,
    "P" => 15,
    "E" => 18
  }

  def parse(quantity, scale \\ 1)

  def parse(quantity, scale) when is_binary(quantity) do
    with [_match, whole, fraction, suffix] <- Regex.run(~r/^\+?(\d+)(?:\.(\d*))?(.*)$/, quantity),
         {numerator, denominator} <- multiplier(suffix) do
      digits = String.to_integer(whole <> fraction)

      div(digits * numerator * scale, Integer.pow(10, String.length(fraction)) * denominator)
    else
      _ -> nil
    end
  end

  def parse(quantity, scale) when is_integer(quantity), do: quantity * scale
  def parse(_quantity, _scale), do: nil

  defp multiplier(suffix) when is_map_key(@binary_suffixes, suffix), do: {Map.fetch!(@binary_suffixes, suffix), 1}

  defp multiplier(suffix) when is_map_key(@decimal_exponents, suffix),
    do: power_of_ten(Map.fetch!(@decimal_exponents, suffix))

  defp multiplier(<<e, exponent::binary>>) when e in [?e, ?E] do
    case Integer.parse(exponent) do
      {exponent, ""} -> power_of_ten(exponent)
      _ -> :error
    end
  end

  defp multiplier(_suffix), do: :error

  defp power_of_ten(exponent) when exponent >= 0, do: {Integer.pow(10, exponent), 1}
  defp power_of_ten(exponent), do: {1, Integer.pow(10, -exponent)}
end
