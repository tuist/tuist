defmodule Pulse.Traces.TempoDuration do
  @moduledoc false
  # Go time.Duration.String spelling over proven nonnegative int64 nanoseconds.
  def format(ns) when is_integer(ns) and ns >= 0 and ns <= 9_223_372_036_854_775_807 do
    cond do
      ns == 0 -> "0s"
      ns < 1000 -> "#{ns}ns"
      ns < 1_000_000 -> decimal(ns, 1000, 3) <> "µs"
      ns < 1_000_000_000 -> decimal(ns, 1_000_000, 6) <> "ms"
      true -> seconds(ns)
    end
  end

  defp seconds(ns) do
    hours = div(ns, 3_600_000_000_000)
    minutes = rem(div(ns, 60_000_000_000), 60)
    h = if hours > 0, do: "#{hours}h", else: ""
    m = if hours > 0 or minutes > 0, do: "#{minutes}m", else: ""
    h <> m <> decimal(rem(ns, 60_000_000_000), 1_000_000_000, 9) <> "s"
  end

  defp decimal(ns, base, precision) do
    case rem(ns, base) do
      0 ->
        Integer.to_string(div(ns, base))

      remainder ->
        fraction = remainder |> Integer.to_string() |> String.pad_leading(precision, "0") |> String.trim_trailing("0")
        "#{div(ns, base)}.#{fraction}"
    end
  end
end
