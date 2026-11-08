defmodule Pulse.PromQL.Time do
  @moduledoc "Exact query timestamp parsing and UTC calendar extraction."
  @max_ns 9_223_372_036_854_775_807
  @absolute_epoch Calendar.ISO.date_to_iso_days(-292_277_022_400, 3, 1)
  @unix_to_absolute (Calendar.ISO.date_to_iso_days(1970, 1, 1) - @absolute_epoch) * 86_400

  # Prometheus stores millisecond timestamps. Avoid a preliminary float
  # rounding of the much larger ns integer for remote-write-aligned values.
  def seconds(ns) when rem(ns, 1_000_000) == 0, do: div(ns, 1_000_000) / 1000
  def seconds(ns), do: ns / 1_000_000_000

  def calendar(name, value) do
    # Go's UTC time.Unix uses unsigned seconds from this absolute epoch.
    # Preserve its wrap at int64 extremes instead of DateTime's year limits.
    absolute = Integer.mod(calendar_seconds(value) + @unix_to_absolute, 18_446_744_073_709_551_616)
    days = div(absolute, 86_400) + @absolute_epoch
    {year, month, day} = Calendar.ISO.date_from_iso_days(days)

    result =
      case name do
        "year" -> year
        "month" -> month
        "day_of_month" -> day
        "day_of_week" -> Integer.mod(days + 6, 7)
        "day_of_year" -> days - Calendar.ISO.date_to_iso_days(year, 1, 1) + 1
        "days_in_month" -> Calendar.ISO.days_in_month(year, month)
        "hour" -> div(rem(absolute, 86_400), 3600)
        "minute" -> div(rem(absolute, 3600), 60)
      end

    result * 1.0
  end

  # Freeze Go 1.25 arm64's float-to-int64 conversion, whose nonfinite and
  # out-of-range behavior is architecture-dependent in Go. Fractions truncate.
  defp calendar_seconds(:nan), do: 0
  defp calendar_seconds(:infinity), do: @max_ns
  defp calendar_seconds(:negative_infinity), do: -@max_ns - 1
  defp calendar_seconds(value) when value >= @max_ns, do: @max_ns
  defp calendar_seconds(value) when value <= -@max_ns - 1, do: -@max_ns - 1
  defp calendar_seconds(value), do: trunc(value)

  def parse_seconds(value) when is_integer(value), do: bounded(value * 1_000_000_000)
  def parse_seconds(value) when is_float(value), do: parse_seconds(Float.to_string(value))

  def parse_seconds(value) when is_binary(value) and byte_size(value) <= 128 do
    case Regex.run(~r/\A([+-]?)(\d+(?:\.\d*)?|\.\d+)(?:[eE]([+-]?\d+))?\z/, value) do
      [_, sign, number] -> decimal(sign, number, 0)
      [_, sign, number, exponent] -> decimal(sign, number, String.to_integer(exponent))
      _ -> {:error, :invalid_timestamp}
    end
  end

  def parse_seconds(_), do: {:error, :invalid_timestamp}

  def parse_timestamp(value) when is_binary(value) do
    case parse_seconds(value) do
      {:ok, _} = result ->
        result

      _ ->
        case DateTime.from_iso8601(value) do
          {:ok, time, _} -> bounded(DateTime.to_unix(time, :nanosecond))
          _ -> {:error, :invalid_timestamp}
        end
    end
  end

  def parse_timestamp(value), do: parse_seconds(value)

  defp decimal(sign, number, exponent) do
    [whole, fraction] =
      case String.split(number, ".", parts: 2) do
        [whole] -> [whole, ""]
        parts -> parts
      end

    coefficient = String.to_integer("0" <> whole <> fraction)
    power = exponent + 9 - byte_size(fraction)

    with {:ok, ns} <- scale(coefficient, power) do
      bounded(if sign == "-", do: -ns, else: ns)
    end
  end

  defp scale(0, _), do: {:ok, 0}
  defp scale(_, power) when power > 19, do: {:error, :invalid_timestamp}
  defp scale(coefficient, power) when power >= 0, do: {:ok, coefficient * Integer.pow(10, power)}
  # A 128-byte input cannot contribute a nanosecond at this scale.
  defp scale(_, power) when power < -128, do: {:ok, 0}

  defp scale(coefficient, power) do
    divisor = Integer.pow(10, -power)
    {:ok, div(coefficient * 2 + divisor, divisor * 2)}
  end

  defp bounded(ns) when ns >= -@max_ns - 1 and ns <= @max_ns, do: {:ok, ns}
  defp bounded(_), do: {:error, :invalid_timestamp}
end
