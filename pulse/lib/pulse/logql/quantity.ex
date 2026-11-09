defmodule Pulse.LogQL.Quantity do
  @moduledoc false

  alias Pulse.PromQL.FloatParser
  alias Pulse.PromQL.Number

  # Exact shared quantities stay isolated from Loki's producer-value and
  # query-token conversion profiles, which intentionally round fractions.
  @max 9_223_372_036_854_775_807
  @duration_units [
    {"ns", 1},
    {"us", 1_000},
    {"µs", 1_000},
    {"ms", 1_000_000},
    {"s", 1_000_000_000},
    {"m", 60_000_000_000},
    {"h", 3_600_000_000_000},
    {"d", 86_400_000_000_000}
  ]
  @byte_units %{
    "" => 1,
    "B" => 1,
    "kB" => 1_000,
    "KB" => 1_000,
    "MB" => 1_000_000,
    "GB" => 1_000_000_000,
    "TB" => 1_000_000_000_000,
    "PB" => 1_000_000_000_000_000,
    "KiB" => 1024,
    "MiB" => 1_048_576,
    "GiB" => 1_073_741_824,
    "TiB" => 1_099_511_627_776,
    "PiB" => 1_125_899_906_842_624
  }

  def duration(text), do: parse(text, :duration)
  def bytes(text), do: parse(text, :bytes)

  # Bracketed ranges use Prometheus model.Duration: ordered, unrepeated integer
  # components, milliseconds at the finest, with no sign or whitespace.
  def duration_literal("0"), do: {:ok, 0}

  def duration_literal(text) when is_binary(text) and text != "" do
    if Regex.match?(
         ~r/\A(?:[0-9]+y)?(?:[0-9]+w)?(?:[0-9]+d)?(?:[0-9]+h)?(?:[0-9]+m)?(?:[0-9]+s)?(?:[0-9]+ms)?\z/,
         text
       ),
       do: parse(text, :duration_literal),
       else: :error
  end

  def duration_literal(_), do: :error

  # Loki first tries the range profile for duration tokens, then Go's duration
  # converter. In particular fractional days/weeks/years never fall through to
  # an exact-decimal extension, while negative hours and repeated units work.
  def duration_query(text) do
    case duration_literal(text) do
      :error -> duration_value(text)
      result -> result
    end
  end

  # Loki producer values use time.ParseDuration/go-humanize, not the exact
  # shared converters. Byte counts are unsigned and fractional runtime
  # quantities intentionally round through float64.
  def duration_value(original) when is_binary(original) do
    {sign, text} =
      case original do
        "-" <> rest -> {-1, rest}
        "+" <> rest -> {1, rest}
        _ -> {1, original}
      end

    result = if text == "0", do: {:ok, 0}, else: duration_value_components(text, 0)

    with {:ok, value} <- result,
         true <- value <= @max or sign == -1 do
      {:ok, sign * value}
    else
      {:error, :missing_unit} -> duration_error("missing unit in duration", original)
      {:error, {:unknown_unit, unit}} -> duration_error("unknown unit #{duration_quote(unit)} in duration", original)
      _ -> duration_error("invalid duration", original)
    end
  end

  def duration_value(_), do: :error

  @runtime_byte_units for {prefix, decimal, binary} <- [
                            {"", 1, 1},
                            {"k", 1_000, 1024},
                            {"m", 1_000_000, 1_048_576},
                            {"g", 1_000_000_000, 1_073_741_824},
                            {"t", 1_000_000_000_000, 1_099_511_627_776},
                            {"p", 1_000_000_000_000_000, 1_125_899_906_842_624},
                            {"e", 1_000_000_000_000_000_000, 1_152_921_504_606_846_976}
                          ],
                          {unit, factor} <-
                            if(prefix == "",
                              do: [{"", 1}, {"b", 1}],
                              else: [
                                {prefix, decimal},
                                {prefix <> "b", decimal},
                                {prefix <> "i", binary},
                                {prefix <> "ib", binary}
                              ]
                            ),
                          into: %{},
                          do: {unit, factor}
  @max_bytes 18_446_744_073_709_551_615

  def bytes_value(text) when is_binary(text) do
    if String.valid?(text), do: parse_bytes_value(text), else: :error
  end

  def bytes_value(_), do: :error

  defp parse_bytes_value(text) do
    # go-humanize counts digit runes, then slices that many *bytes*. The
    # scanned characters are all separate graphemes. PCRE2's Unicode 16 Nd
    # table needs Unicode 17's Tolong Siki digits to match Go 1.27.
    [prefix] = Regex.run(~r/\A[\p{Nd}\x{11DE0}-\x{11DE9}.,]*/u, text)
    size = String.length(prefix)
    <<number::binary-size(^size), suffix::binary>> = text
    number = String.replace(number, ",", "")

    with {:ok, float} <- byte_number(number),
         {:ok, factor} <- byte_factor(suffix),
         {:ok, _bytes} = result <- scale_bytes_value(number, float, factor) do
      result
    else
      :error -> {:error, "too large: " <> text}
      {:error, _details} = error -> error
    end
  end

  defp byte_factor(suffix) do
    # Go uses simple lowercasing: U+0130 becomes i without a combining dot.
    suffix = suffix |> String.trim() |> String.replace("İ", "I") |> String.downcase()

    case Map.fetch(@runtime_byte_units, suffix) do
      {:ok, factor} -> {:ok, factor}
      :error -> {:error, "unhandled size name: " <> suffix}
    end
  end

  defp byte_number(number) do
    case FloatParser.parse(number) do
      {:ok, float} ->
        {:ok, float}

      :error ->
        reason =
          if Regex.match?(~r/\A(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)\z/, number),
            do: "value out of range",
            else: "invalid syntax"

        quoted = IO.iodata_to_binary([?", byte_number_quote(number), ?"])
        {:error, "strconv.ParseFloat: parsing #{quoted}: #{reason}"}
    end
  end

  # Only decimal digits/dots survive prefix scanning and comma removal:
  # complete runes print literally; a truncated UTF-8 rune uses strconv hex.
  defp byte_number_quote(""), do: []
  defp byte_number_quote(<<char::utf8, rest::binary>>), do: [<<char::utf8>> | byte_number_quote(rest)]

  defp byte_number_quote(<<byte, rest::binary>>),
    do: ["\\x", Base.encode16(<<byte>>, case: :lower) | byte_number_quote(rest)]

  defp scale_bytes_value(number, float, factor) do
    if String.contains?(number, ".") do
      value = Number.multiply(float, factor)
      if is_float(value) and value < 18_446_744_073_709_551_616.0, do: {:ok, trunc(value)}, else: :error
    else
      with {:ok, value} <- integer(number, div(@max_bytes, factor), 0), do: {:ok, value * factor}
    end
  end

  defp duration_value_components("", _total), do: :error

  defp duration_value_components(text, total) do
    with {:ok, whole, fraction, rest} <- number(text),
         {:ok, integral} <- integer(whole, @max + 1, 0),
         size when size > 0 <- unit_length(rest, 0),
         <<unit::binary-size(^size), tail::binary>> = rest,
         {:ok, factor} <- duration_value_unit(unit),
         value = total + integral * factor + duration_value_fraction(fraction, factor),
         true <- value <= @max + 1 do
      case tail do
        "" -> {:ok, value}
        _ -> duration_value_components(tail, value)
      end
    else
      0 -> {:error, :missing_unit}
      {:error, _reason} = error -> error
      _ -> :error
    end
  end

  defp duration_error(message, value), do: {:error, "time: #{message} #{duration_quote(value)}"}

  # time.ParseDuration uses a byte-oriented quote, not JSON or strconv.Quote:
  # controls/non-ASCII bytes use lowercase hex, while DEL stays unescaped.
  defp duration_quote(text) do
    escaped =
      for <<byte <- text>>, into: "" do
        cond do
          byte in [?", ?\\] -> <<?\\, byte>>
          byte < 32 or byte >= 128 -> "\\x" <> Base.encode16(<<byte>>, case: :lower)
          true -> <<byte>>
        end
      end

    "\"" <> escaped <> "\""
  end

  for {unit, factor} <- @duration_units, unit != "d" do
    defp duration_value_unit(unquote(unit)), do: {:ok, unquote(factor)}
  end

  defp duration_value_unit("μs"), do: {:ok, 1_000}
  defp duration_value_unit(unit), do: {:error, {:unknown_unit, unit}}

  defp unit_length(<<char, _::binary>>, size) when char == ?. or char in ?0..?9, do: size
  defp unit_length(<<_, rest::binary>>, size), do: unit_length(rest, size + 1)
  defp unit_length("", size), do: size

  defp duration_value_fraction(text, factor) do
    {value, scale} = duration_value_fraction(text, 0, 1.0)
    if scale == :infinity, do: 0, else: trunc(value * (factor / scale))
  end

  defp duration_value_fraction("", value, scale), do: {value, scale}

  defp duration_value_fraction(<<digit, rest::binary>>, value, scale) do
    next = value * 10 + digit - ?0

    if value > div(@max, 10) or next > @max + 1,
      do: {value, scale},
      else: duration_value_fraction(rest, next, Number.multiply(scale, 10.0))
  end

  defp parse(text, kind) when is_binary(text) do
    {sign, text} =
      case text do
        "-" <> rest -> {-1, rest}
        "+" <> rest -> {1, rest}
        _ -> {1, text}
      end

    limit = if sign == -1, do: @max + 1, else: @max

    case magnitude(text, kind, limit) do
      {:ok, value} -> {:ok, sign * value}
      :error -> :error
    end
  end

  defp parse(_, _), do: :error

  defp magnitude("", _kind, _limit), do: :error
  defp magnitude("0", :duration, _limit), do: {:ok, 0}
  defp magnitude(text, :bytes, limit), do: byte_value(text, limit)
  defp magnitude(text, kind, limit), do: components(text, 0, limit, kind)

  defp components("", total, _limit, _kind), do: {:ok, total}

  defp components(text, total, limit, kind) do
    with {:ok, whole, fraction, rest} <- number(text),
         {factor, rest} <- duration_unit(rest, kind),
         {:ok, value} <- scale(whole, fraction, factor, limit - total) do
      components(rest, total + value, limit, kind)
    else
      _ -> :error
    end
  end

  defp byte_value(text, limit) do
    with {:ok, whole, fraction, unit} <- number(text),
         factor when is_integer(factor) <- Map.get(@byte_units, unit) do
      scale(whole, fraction, factor, limit)
    else
      _ -> :error
    end
  end

  # Prometheus-style query literals additionally allow weeks/years. Runtime
  # producer values deliberately do not infer those units from literal syntax.
  defp duration_unit("w" <> rest, :duration_literal), do: {604_800_000_000_000, rest}
  defp duration_unit("y" <> rest, :duration_literal), do: {31_536_000_000_000_000, rest}
  defp duration_unit(text, _kind), do: duration_unit(text)

  for {unit, factor} <- @duration_units do
    defp duration_unit(unquote(unit) <> rest), do: {unquote(factor), rest}
  end

  defp duration_unit(_), do: :error

  defp number(text) do
    length = digits(text, 0)
    <<whole::binary-size(^length), rest::binary>> = text

    {fraction, rest} =
      case rest do
        "." <> tail ->
          length = digits(tail, 0)
          <<fraction::binary-size(^length), rest::binary>> = tail
          {fraction, rest}

        _ ->
          {"", rest}
      end

    if whole == "" and fraction == "", do: :error, else: {:ok, whole, fraction, rest}
  end

  defp digits(<<digit, rest::binary>>, n) when digit in ?0..?9, do: digits(rest, n + 1)
  defp digits(_, n), do: n

  defp scale(whole, fraction, factor, limit) do
    with {:ok, integral} <- integer(whole, div(limit, factor), 0),
         value = integral * factor + fractional(fraction, byte_size(fraction) - 1, factor, 0),
         true <- value <= limit do
      {:ok, value}
    else
      _ -> :error
    end
  end

  defp integer("", _limit, value), do: {:ok, value}

  defp integer(<<digit, rest::binary>>, limit, value) do
    digit = digit - ?0
    if digit <= limit and value <= div(limit - digit, 10), do: integer(rest, limit, value * 10 + digit), else: :error
  end

  # Right-to-left long multiplication computes trunc(fraction * factor).
  # Carry is always smaller than factor, independent of fraction length.
  defp fractional(_text, index, _factor, carry) when index < 0, do: carry

  defp fractional(text, index, factor, carry),
    do: fractional(text, index - 1, factor, div((:binary.at(text, index) - ?0) * factor + carry, 10))
end
