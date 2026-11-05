defmodule Pulse.PromQL.FloatParser do
  @moduledoc false
  import Bitwise

  alias Pulse.GoUnicode

  @digits "[0-9](?:_?[0-9])*"
  @hex "[0-9a-fA-F](?:_?[0-9a-fA-F])*"
  @decimal Regex.compile!("\\A[+-]?(?:#{@digits}(?:\\.(?:#{@digits})?)?|\\.#{@digits})(?:[eE][+-]?#{@digits})?\\z")
  @hex_float Regex.compile!("\\A([+-]?)0[xX]_?((?:#{@hex})(?:\\.(?:#{@hex})?)?|\\.#{@hex})[pP]([+-]?#{@digits})\\z")
  @hex_integer Regex.compile!("\\A([+-]?)0[xX]_?(#{@hex})\\z")

  # Histogram boundaries use strconv.ParseFloat's grammar. Query literals also
  # admit hexadecimal integers, which Prometheus parses as integer literals.
  def parse(text, mode \\ :float)

  def parse(text, mode) when is_binary(text) do
    if String.valid?(text), do: parse_valid(text, mode), else: :error
  end

  def parse(_, _), do: :error

  # Keep the existing parse/literal API while exposing Go's complete error
  # details to LogQL. Malformed overflowing input is syntax, not range failure.
  def parse_with_error(text) when is_binary(text) do
    case parse(text) do
      {:ok, _value} = result ->
        result

      :error ->
        reason =
          if Regex.match?(@decimal, text) or Regex.match?(@hex_float, text),
            do: "value out of range",
            else: "invalid syntax"

        quoted = GoUnicode.quote(text)
        {:error, "strconv.ParseFloat: parsing #{quoted}: #{reason}"}
    end
  end

  def parse_with_error(_), do: :error

  defp parse_valid(text, mode) do
    case String.downcase(text) do
      "nan" -> {:ok, :nan}
      inf when inf in ["inf", "+inf", "infinity", "+infinity"] -> {:ok, :infinity}
      inf when inf in ["-inf", "-infinity"] -> {:ok, :negative_infinity}
      _ -> parse_numeric(text, mode)
    end
  end

  defp parse_numeric(text, mode) do
    cond do
      Regex.match?(@decimal, text) -> decimal(text, mode)
      Regex.match?(@hex_float, text) -> hexadecimal(Regex.run(@hex_float, text))
      mode == :literal and Regex.match?(@hex_integer, text) -> hex_integer(Regex.run(@hex_integer, text))
      true -> :error
    end
  rescue
    ArgumentError -> :error
    ArithmeticError -> :error
  end

  defp decimal(text, :literal) do
    plain = String.replace(text, "_", "")
    if Regex.match?(~r/\A0[0-7]+\z/, plain), do: octal_literal(plain), else: decimal(text, :float)
  end

  defp decimal(text, _mode) do
    text = String.replace(text, "_", "")
    text = Regex.replace(~r/\.(?=[eE]|$)/, text, ".0")
    text = Regex.replace(~r/\A([+-]?)\./, text, "\\g{1}0.")

    case Float.parse(text) do
      {value, ""} -> {:ok, value}
      _ -> :error
    end
  end

  defp octal_literal(text) do
    integer = String.to_integer(text, 8)
    if integer < 9_223_372_036_854_775_808, do: {:ok, integer / 1}, else: decimal(text, :float)
  end

  defp hex_integer([_, sign, digits]) do
    integer = digits |> String.replace("_", "") |> String.to_integer(16)
    if integer < 9_223_372_036_854_775_808, do: {:ok, signed(integer / 1, sign)}, else: :error
  end

  defp hexadecimal([_, sign, digits, exponent]) do
    digits = String.replace(digits, "_", "")

    fractional_digits =
      case String.split(digits, ".") do
        [_, fraction] -> byte_size(fraction)
        _ -> 0
      end

    mantissa = digits |> String.replace(".", "") |> String.to_integer(16)
    exponent = String.to_integer(String.replace(exponent, "_", "")) - 4 * fractional_digits
    binary_float(mantissa, exponent, sign)
  end

  defp binary_float(0, _exponent, sign), do: {:ok, signed(0.0, sign)}

  defp binary_float(mantissa, exponent, sign) do
    # Round once, to nearest-even, including the subnormal precision boundary.
    bits = bit_length(mantissa)
    shift = max(max(bits - 53, -1074 - exponent), 0)
    rounded = round_binary(mantissa, shift, bits)
    exponent = exponent + shift
    finish_binary(rounded, exponent, sign)
  end

  defp finish_binary(0, _exponent, sign), do: {:ok, signed(0.0, sign)}

  defp finish_binary(mantissa, exponent, sign) do
    if bit_length(mantissa) + exponent - 1 > 1023 do
      :error
    else
      {:ok, signed(mantissa * :math.pow(2.0, exponent), sign)}
    end
  end

  defp round_binary(mantissa, 0, _bits), do: mantissa
  defp round_binary(_mantissa, shift, bits) when shift > bits, do: 0

  defp round_binary(mantissa, shift, _bits) do
    high = mantissa >>> shift
    lost = mantissa - (high <<< shift)
    half = 1 <<< (shift - 1)
    if lost > half or (lost == half and rem(high, 2) == 1), do: high + 1, else: high
  end

  defp bit_length(integer), do: integer |> Integer.to_string(2) |> byte_size()
  defp signed(value, "-"), do: -value
  defp signed(value, _), do: value
end
