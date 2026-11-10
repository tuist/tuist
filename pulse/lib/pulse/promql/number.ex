defmodule Pulse.PromQL.Number do
  @moduledoc """
  IEEE-754 values that the BEAM cannot represent as floats use a closed atom
  vocabulary. Staleness is a storage marker, not an arithmetic NaN.
  """
  def valid?(value), do: is_number(value) or value in [:nan, :infinity, :negative_infinity, :stale]
  def nan?(:nan), do: true
  def nan?(_), do: false
  def negate(:nan), do: :nan
  def negate(:infinity), do: :negative_infinity
  def negate(:negative_infinity), do: :infinity
  def negate(value), do: -value

  def add(:nan, _), do: :nan
  def add(_, :nan), do: :nan
  def add(:infinity, :negative_infinity), do: :nan
  def add(:negative_infinity, :infinity), do: :nan
  def add(:infinity, _), do: :infinity
  def add(_, :infinity), do: :infinity
  def add(:negative_infinity, _), do: :negative_infinity
  def add(_, :negative_infinity), do: :negative_infinity
  def add(a, b), do: finite(fn -> a + b end, sign(a))

  def multiply(:nan, _), do: :nan
  def multiply(_, :nan), do: :nan
  def multiply(a, b) when is_number(a) and is_number(b), do: finite(fn -> a * b end, sign(a) * sign(b))
  def multiply(a, b) when a == 0 or b == 0, do: :nan
  def multiply(a, b), do: infinity(sign(a) * sign(b))

  def divide(:nan, _), do: :nan
  def divide(_, :nan), do: :nan
  def divide(a, b) when a in [:infinity, :negative_infinity] and b in [:infinity, :negative_infinity], do: :nan
  def divide(a, b) when b in [:infinity, :negative_infinity], do: 0.0 * sign(a) * sign(b)
  def divide(a, b) when a == 0 and b == 0, do: :nan
  def divide(a, b) when b == 0 or a in [:infinity, :negative_infinity], do: infinity(sign(a) * sign(b))
  def divide(a, b), do: finite(fn -> a / b end, sign(a) * sign(b))

  def binary("+", a, b), do: add(a, b)
  def binary("-", a, b), do: add(a, negate(b))
  def binary("*", a, b), do: multiply(a, b)
  def binary("/", a, b), do: divide(a, b)
  def binary("%", a, b) when is_number(a) and is_number(b) and b != 0, do: :math.fmod(a, b)
  def binary("%", a, b) when is_number(a) and b in [:infinity, :negative_infinity], do: a
  def binary("%", _, _), do: :nan
  def binary("^", a, b), do: power(a, b)
  def binary("atan2", a, b), do: arctangent(a, b)

  defp arctangent(:nan, _), do: :nan
  defp arctangent(_, :nan), do: :nan

  defp arctangent(a, b) when a in [:infinity, :negative_infinity] and b in [:infinity, :negative_infinity],
    do: sign(a) * if(sign(b) > 0, do: :math.pi() / 4, else: 3 * :math.pi() / 4)

  defp arctangent(a, _) when a in [:infinity, :negative_infinity], do: sign(a) * (:math.pi() / 2)

  defp arctangent(a, b) when b in [:infinity, :negative_infinity],
    do: sign(a) * if(sign(b) > 0, do: 0.0, else: :math.pi())

  defp arctangent(a, b), do: :math.atan2(a, b)

  defp power(a, b) when b == 0 or a == 1, do: 1.0
  defp power(:nan, _), do: :nan
  defp power(_, :nan), do: :nan

  defp power(a, b) when b in [:infinity, :negative_infinity] do
    magnitude = if sign(a) < 0, do: negate(a), else: a

    cond do
      magnitude == 1 -> 1.0
      compare(">", magnitude, 1) == (b == :infinity) -> :infinity
      true -> 0.0
    end
  end

  defp power(a, b) when a in [:infinity, :negative_infinity] do
    result_sign = if a == :negative_infinity and odd_integer?(b), do: -1, else: 1
    if b > 0, do: infinity(result_sign), else: 0.0 * result_sign
  end

  defp power(a, b) when a == 0 and b < 0 do
    infinity(if(odd_integer?(b), do: sign(a), else: 1))
  end

  defp power(a, b) when a < 0 and trunc(b) != b, do: :nan

  defp power(a, b) do
    :math.pow(a, b)
  rescue
    ArithmeticError -> infinity(if(a < 0 and odd_integer?(b), do: -1, else: 1))
  end

  defp odd_integer?(value), do: is_number(value) and trunc(value) == value and rem(trunc(value), 2) != 0

  def sum(values) do
    {sum, correction} =
      Enum.reduce(values, {0.0, 0.0}, fn value, {sum, correction} ->
        compensated_add(value, sum, correction)
      end)

    add(sum, correction)
  end

  # Port of Prometheus's Neumaier-improved kahanSumInc, including its infinity
  # short-circuit. Keep the correction separate until the final result.
  def compensated_add(value, sum, correction) do
    total = add(sum, value)

    cond do
      total in [:infinity, :negative_infinity] ->
        {total, 0.0}

      compare(">=", magnitude(sum), magnitude(value)) ->
        {total, add(correction, add(binary("-", sum, total), value))}

      true ->
        {total, add(correction, add(binary("-", value, total), sum))}
    end
  end

  defp magnitude(:nan), do: :nan
  defp magnitude(value), do: if(sign(value) < 0, do: negate(value), else: value)

  def average([first | rest]), do: rest |> Enum.reduce(average_start(first), &average_step/2) |> average_value()

  @doc "`average/1` one value at a time: `average_start/1`, `average_step/2`, then `average_value/1`."
  def average_start(first), do: %{sum: first, correction: 0.0, count: 1, mean: 0.0, incremental?: false}

  def average_value(state) do
    if state.incremental?,
      do: add(state.mean, state.correction),
      else: add(divide(state.sum, state.count), divide(state.correction, state.count))
  end

  def average_step(value, state) do
    state = %{state | count: state.count + 1}
    state = average_sum(value, state)

    if state.incremental? do
      q = (state.count - 1) / state.count

      {mean, correction} =
        compensated_add(divide(value, state.count), multiply(q, state.mean), multiply(q, state.correction))

      %{state | mean: mean, correction: correction}
    else
      state
    end
  end

  defp average_sum(_value, %{incremental?: true} = state), do: state

  defp average_sum(value, state) do
    {sum, correction} = compensated_add(value, state.sum, state.correction)

    if sum in [:infinity, :negative_infinity] do
      %{
        state
        | incremental?: true,
          mean: divide(state.sum, state.count - 1),
          correction: divide(state.correction, state.count - 1)
      }
    else
      %{state | sum: sum, correction: correction}
    end
  end

  def compare("!=", a, b), do: not compare("==", a, b)
  def compare(_, :nan, _), do: false
  def compare(_, _, :nan), do: false
  def compare("==", a, b), do: a == b
  def compare("<", a, b), do: less?(a, b)
  def compare(">", a, b), do: less?(b, a)
  def compare("<=", a, b), do: a == b or less?(a, b)
  def compare(">=", a, b), do: a == b or less?(b, a)

  def less?(:nan, _), do: false
  def less?(_, :nan), do: false
  def less?(:negative_infinity, b), do: b != :negative_infinity
  def less?(a, :infinity), do: a != :infinity
  def less?(:infinity, _), do: false
  def less?(_, :negative_infinity), do: false
  def less?(a, b), do: a < b
  def min(:nan, b), do: b
  def min(a, :nan), do: a
  def min(a, b), do: if(less?(a, b), do: a, else: b)
  def max(:nan, b), do: b
  def max(a, :nan), do: a
  def max(a, b), do: if(less?(a, b), do: b, else: a)

  # Scalar math.Min/Max differ from aggregation: the selected infinity wins
  # even over NaN; otherwise NaN propagates. Zero ties retain the correct sign.
  def extremum("min_of", a, b) when a == :negative_infinity or b == :negative_infinity, do: :negative_infinity
  def extremum("max_of", a, b) when a == :infinity or b == :infinity, do: :infinity
  def extremum(_, :nan, _), do: :nan
  def extremum(_, _, :nan), do: :nan
  def extremum("min_of", a, b) when a == 0 and b == 0, do: if(sign(a) < 0, do: a, else: b)
  def extremum("max_of", a, b) when a == 0 and b == 0, do: if(sign(a) < 0, do: b, else: a)
  def extremum("min_of", a, b), do: __MODULE__.min(a, b)
  def extremum("max_of", a, b), do: __MODULE__.max(a, b)

  def sign(:infinity), do: 1
  def sign(:negative_infinity), do: -1
  def sign(value) when is_number(value), do: if(value < 0 or (value == 0 and negative_zero?(value)), do: -1, else: 1)
  defp negative_zero?(value) when is_float(value), do: <<value::float-64>> == <<0x8000000000000000::64>>
  defp negative_zero?(_), do: false
  defp infinity(sign), do: if(sign < 0, do: :negative_infinity, else: :infinity)

  defp finite(fun, sign) do
    fun.()
  rescue
    ArithmeticError -> infinity(sign)
  end

  def format(:nan), do: "NaN"
  def format(:infinity), do: "+Inf"
  def format(:negative_infinity), do: "-Inf"

  # count_values uses Go's shortest fixed decimal for floats and shortest
  # general format for histogram text. Neither uses the HTTP sample cutoffs.
  def format(value, _mode) when is_atom(value), do: format(value)

  def format(value, :open_metrics) do
    text = if value == 0, do: "0", else: format(value, :general)
    if String.contains?(text, [".", "e"]), do: text, else: text <> ".0"
  end

  def format(value, mode) do
    raw = :erlang.float_to_binary(value / 1, [:short])
    {sign, raw} = if String.starts_with?(raw, "-"), do: {"-", String.trim_leading(raw, "-")}, else: {"", raw}
    [mantissa | exp] = String.split(raw, "e")
    exponent = if exp == [], do: 0, else: String.to_integer(hd(exp))
    point = mantissa |> String.split(".") |> hd() |> byte_size()
    all = String.replace(mantissa, ".", "")
    rest = String.trim_leading(all, "0")
    digits = String.trim_trailing(rest, "0")
    exponent = point + exponent - (byte_size(all) - byte_size(rest)) - 1
    sign <> decimal(digits, exponent, mode)
  end

  defp decimal("", _, _), do: "0"

  defp decimal(digits, exponent, :general) when exponent < -4 or exponent >= 6 do
    <<first::binary-size(1), tail::binary>> = digits
    tail = if tail == "", do: "", else: "." <> tail
    sign = if exponent < 0, do: "-", else: "+"
    first <> tail <> "e" <> sign <> String.pad_leading(Integer.to_string(abs(exponent)), 2, "0")
  end

  defp decimal(digits, exponent, _) when exponent < 0, do: "0." <> String.duplicate("0", -exponent - 1) <> digits

  defp decimal(digits, exponent, _) do
    point = exponent + 1

    if point >= byte_size(digits) do
      String.pad_trailing(digits, point, "0")
    else
      <<left::binary-size(^point), right::binary>> = digits
      left <> "." <> right
    end
  end
end
