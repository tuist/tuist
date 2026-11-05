defmodule Pulse.OTLP.Integer do
  @moduledoc false

  # ProtoJSON integer strings may use decimal/exponent notation, but must
  # represent an exact integer. Never round through a float or construct a
  # bignum/power proportional to an untrusted exponent.
  @number ~r/\A(-?)(0|[1-9][0-9]*)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?\z/

  def parse(value) do
    case Regex.run(@number, value, capture: :all_but_first) do
      [sign, whole | rest] ->
        fraction = Enum.at(rest, 0, "")
        exponent = Enum.at(rest, 1, "")
        coefficient = String.trim_leading(whole <> fraction, "0")
        exact(sign, coefficient, byte_size(fraction), exponent)

      _ ->
        :error
    end
  end

  defp exact(_sign, "", _fraction, _exponent), do: {:ok, 0}

  defp exact(sign, coefficient, fraction, exponent) do
    core = String.trim_trailing(coefficient, "0")
    shift = exponent(exponent, byte_size(coefficient) + fraction + 20) - fraction
    shift = shift + byte_size(coefficient) - byte_size(core)

    if shift >= 0 and byte_size(core) + shift <= 20 do
      {:ok, String.to_integer(sign <> core <> String.duplicate("0", shift))}
    else
      :error
    end
  end

  defp exponent("", _limit), do: 0

  defp exponent(value, limit) do
    {sign, digits} =
      case value do
        <<"-", rest::binary>> -> {-1, rest}
        <<"+", rest::binary>> -> {1, rest}
        rest -> {1, rest}
      end

    digits = String.trim_leading(digits, "0")
    # Saturate before decimal construction. Larger shifts cannot make a
    # nonzero bounded coefficient into a uint64/int64.
    magnitude =
      if byte_size(digits) > byte_size(Integer.to_string(limit)) do
        limit + 1
      else
        min(String.to_integer("0" <> digits), limit + 1)
      end

    sign * magnitude
  end
end
