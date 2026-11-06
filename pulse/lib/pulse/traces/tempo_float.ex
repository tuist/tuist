defmodule Pulse.Traces.TempoFloat do
  @moduledoc false

  # Independent BEAM shortest-roundtrip conversion followed by TraceQL's Go
  # general-format exponent rules and mandatory fixed integral decimal suffix.
  def format("NaN"), do: "NaN.0"
  def format("Infinity"), do: "+Inf.0"
  def format("-Infinity"), do: "-Inf.0"

  def format(value) when is_number(value) do
    raw = :erlang.float_to_binary(value / 1, [:short])
    {sign, raw} = if String.starts_with?(raw, "-"), do: {"-", String.trim_leading(raw, "-")}, else: {"", raw}
    [mantissa | exp] = String.split(raw, "e")
    exponent = if exp == [], do: 0, else: String.to_integer(hd(exp))
    point = mantissa |> String.split(".") |> hd() |> byte_size()
    all = String.replace(mantissa, ".", "")
    rest = String.trim_leading(all, "0")
    digits = String.trim_trailing(rest, "0")
    exponent = point + exponent - (byte_size(all) - byte_size(rest)) - 1
    sign <> render(digits, exponent)
  end

  defp render("", _exponent), do: "0.0"

  defp render(digits, exponent) when exponent < -4 or exponent >= 6 do
    <<first::binary-size(1), tail::binary>> = digits
    tail = if tail == "", do: "", else: "." <> tail
    sign = if exponent < 0, do: "-", else: "+"
    first <> tail <> "e" <> sign <> String.pad_leading(Integer.to_string(abs(exponent)), 2, "0")
  end

  defp render(digits, exponent) when exponent < 0, do: "0." <> String.duplicate("0", -exponent - 1) <> digits

  defp render(digits, exponent) do
    point = exponent + 1

    if point >= byte_size(digits) do
      String.pad_trailing(digits, point, "0") <> ".0"
    else
      <<left::binary-size(^point), right::binary>> = digits
      left <> "." <> right
    end
  end
end
