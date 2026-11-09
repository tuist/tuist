defmodule Pulse.Loki.FieldType do
  @moduledoc """
  Loki's detected-field typing: the first of Go's `strconv.ParseInt`,
  `strconv.ParseFloat`, `strconv.ParseBool`, `time.ParseDuration` and
  go-humanize's `ParseBytes` that accepts a value names its type, otherwise
  it is a string. Also go-humanize's byte formatting, which Loki applies to
  byte-sized detected field values.
  """

  import Bitwise

  @max_int64 (1 <<< 63) - 1
  @min_int64 -(1 <<< 63)
  @bools ~w(1 t T TRUE true True 0 f F FALSE false False)

  @duration_units %{
    "ns" => 1,
    "us" => 1_000,
    "µs" => 1_000,
    "μs" => 1_000,
    "ms" => 1_000_000,
    "s" => 1_000_000_000,
    "m" => 60_000_000_000,
    "h" => 3_600_000_000_000
  }

  @byte_sizes %{
    "" => 1,
    "b" => 1,
    "k" => 1_000,
    "kb" => 1_000,
    "ki" => 1 <<< 10,
    "kib" => 1 <<< 10,
    "m" => 1_000_000,
    "mb" => 1_000_000,
    "mi" => 1 <<< 20,
    "mib" => 1 <<< 20,
    "g" => 1_000_000_000,
    "gb" => 1_000_000_000,
    "gi" => 1 <<< 30,
    "gib" => 1 <<< 30,
    "t" => 1_000_000_000_000,
    "tb" => 1_000_000_000_000,
    "ti" => 1 <<< 40,
    "tib" => 1 <<< 40,
    "p" => 1_000_000_000_000_000,
    "pb" => 1_000_000_000_000_000,
    "pi" => 1 <<< 50,
    "pib" => 1 <<< 50,
    "e" => 1_000_000_000_000_000_000,
    "eb" => 1_000_000_000_000_000_000,
    "ei" => 1 <<< 60,
    "eib" => 1 <<< 60
  }

  @doc "The Loki detected-field type name of `value`."
  @spec detect(String.t()) :: String.t()
  def detect(value) do
    cond do
      int?(value) -> "int"
      float?(value) -> "float"
      value in @bools -> "boolean"
      duration?(value) -> "duration"
      bytes(value) != :error -> "bytes"
      true -> "string"
    end
  end

  defp int?(value) do
    Regex.match?(~r/\A[+-]?[0-9]+\z/, value) and
      String.to_integer(value) in @min_int64..@max_int64
  end

  defp float?(value), do: parse_float(value) != :error

  # Go's ParseFloat: decimal and hexadecimal forms, infinities and NaN.
  # Values that overflow a double are errors; underflow is not.
  defp parse_float(value) do
    cond do
      Regex.match?(~r/\A[+-]?(inf|infinity)\z/i, value) -> :ok
      Regex.match?(~r/\Anan\z/i, value) -> :ok
      match = Regex.run(~r/\A([+-]?)([0-9]*)(?:\.([0-9]*))?(?:[eE]([+-]?[0-9]+))?\z/, value) -> decimal(match)
      match = Regex.run(~r/\A[+-]?0[xX]([0-9a-fA-F]*)(?:\.([0-9a-fA-F]*))?[pP]([+-]?[0-9]+)\z/, value) -> hex(match)
      true -> :error
    end
  end

  defp decimal([_, sign, int, frac | rest]) do
    frac = frac || ""

    if int == "" and frac == "" do
      :error
    else
      exp = List.first(rest) || "0"
      digits = String.to_integer(sign <> pad(int <> frac))
      finite?(digits, String.to_integer(exp) - byte_size(frac), 10)
    end
  end

  defp decimal([_, sign, int]), do: decimal([nil, sign, int, ""])

  defp hex([_, int, frac, exp]) do
    if int == "" and frac == "",
      do: :error,
      else: finite?(String.to_integer(pad(int <> frac), 16), String.to_integer(exp) - 4 * byte_size(frac), 2)
  end

  defp pad(""), do: "0"
  defp pad(digits), do: digits

  # mantissa * base^exp fits in a double (|x| < 2^1024, rounding aside).
  defp finite?(0, _exp, _base), do: :ok

  defp finite?(mantissa, exp, base) do
    magnitude = :math.log2(abs(mantissa)) + exp * :math.log2(base)
    if magnitude < 1024, do: :ok, else: :error
  end

  # Go's ParseDuration: an optional sign, then one or more decimal numbers
  # with a unit; "0" alone needs none. The total must fit in int64 nanoseconds.
  defp duration?("0"), do: true
  defp duration?("+0"), do: true
  defp duration?("-0"), do: true

  defp duration?(value) do
    case Regex.run(~r/\A([+-]?)((?:(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:ns|us|µs|μs|ms|s|m|h))+)\z/u, value) do
      [_, sign, body] ->
        total =
          ~r/([0-9]*)(?:\.([0-9]*))?(ns|us|µs|μs|ms|s|m|h)/u
          |> Regex.scan(body)
          |> Enum.reduce(0, fn [_, int, frac, unit], acc -> acc + segment_ns(int, frac, @duration_units[unit]) end)

        if sign == "-", do: total <= -@min_int64, else: total <= @max_int64

      nil ->
        false
    end
  end

  defp segment_ns(int, frac, unit) do
    whole = String.to_integer(pad(int)) * unit
    if frac == "", do: whole, else: whole + div(String.to_integer(frac) * unit, 10 ** byte_size(frac))
  end

  @doc "go-humanize `ParseBytes`: `{:ok, bytes}` or `:error`."
  @spec bytes(String.t()) :: {:ok, non_neg_integer()} | :error
  def bytes(value) do
    {num, rest} = split_number(value, "")
    num = String.replace(num, ",", "")
    unit = rest |> String.trim() |> String.downcase()

    with {:ok, size} <- Map.fetch(@byte_sizes, unit),
         {:ok, f} <- go_float(num),
         product = f * size,
         true <- product < 18_446_744_073_709_551_615.0 do
      {:ok, trunc(product)}
    else
      _ -> :error
    end
  end

  # Leading digits, dots and commas, as ParseBytes scans them.
  defp split_number(<<c::utf8, rest::binary>>, acc) when c in ?0..?9 or c in [?., ?,],
    do: split_number(rest, acc <> <<c::utf8>>)

  defp split_number(rest, acc), do: {acc, rest}

  defp go_float(num) do
    case parse_float(num) do
      :ok -> {:ok, num |> float_text() |> String.to_float()}
      :error -> :error
    end
  end

  defp float_text(num) do
    [int, frac] =
      case String.split(num, ".", parts: 2) do
        [int] -> [int, ""]
        parts -> parts
      end

    pad(int) <> "." <> pad(frac)
  end

  @doc "go-humanize `Bytes` without the space Loki removes: `1500000` is `1.5MB`."
  @spec format_bytes(non_neg_integer()) :: String.t()
  def format_bytes(bytes) when bytes < 10, do: "#{bytes}B"

  def format_bytes(bytes) do
    sizes = ~w(B kB MB GB TB PB EB)
    e = floor(:math.log(bytes) / :math.log(1000))
    val = Float.floor(bytes / 1000 ** e * 10 + 0.5) / 10
    text = if val < 10, do: :erlang.float_to_binary(val, decimals: 1), else: :erlang.float_to_binary(val, decimals: 0)
    text <> Enum.at(sizes, e)
  end
end
