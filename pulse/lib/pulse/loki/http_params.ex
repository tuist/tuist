defmodule Pulse.Loki.HTTPParams do
  @moduledoc "Bounded Loki HTTP numeric, timestamp and window parameter parsing."

  alias Pulse.LogQL.Quantity
  alias Pulse.PromQL.FloatParser

  @second 1_000_000_000
  @hour 3600 * @second
  @max 9_223_372_036_854_775_807
  @min -9_223_372_036_854_775_808

  def query(params, mode, now \\ System.system_time(:nanosecond))

  def query(params, :range, now) do
    with {:ok, window} <- bounds(params, now),
         :ok <- ordered(window),
         {:ok, limit} <- uint32(params["limit"], "limit", 100),
         {:ok, direction} <- direction(params["direction"]),
         {:ok, step} <- step(params["step"], window.start_ns, window.end_ns),
         {:ok, interval} <- interval(params["interval"]) do
      {:ok,
       %{
         start_ts_ns: window.start_ns,
         end_ts_ns: window.end_ns,
         limit: limit,
         direction: direction,
         step_ns: step,
         interval_ns: interval
       }}
    end
  end

  def query(params, :instant, now) do
    with {:ok, limit} <- uint32(params["limit"], "limit", 100),
         {:ok, time} <- timestamp(params["time"], nil, "time"),
         {:ok, finish} <- timestamp(params["end"], now, "end"),
         {:ok, start} <- timestamp(params["start"], nil, "start"),
         finish = time || finish,
         :ok <- ordered(%{start_ns: start || finish, end_ns: finish}),
         {:ok, direction} <- direction(params["direction"]) do
      opts = %{end_ts_ns: finish, limit: limit, direction: direction}
      {:ok, if(is_nil(start), do: opts, else: Map.put(opts, :start_ts_ns, start))}
    end
  end

  def bounds(params, now \\ System.system_time(:nanosecond)) do
    with {:ok, since} <- since(params["since"]),
         {:ok, finish} <- timestamp(params["end"], now, "end"),
         {:ok, start} <- timestamp(params["start"], max(@min, min(finish, now) - since), "start") do
      {:ok, %{start_ns: start, end_ns: finish}}
    end
  end

  def ordered(%{start_ns: start, end_ns: finish}) when start > finish,
    do: error("start/end", "end timestamp must not be before or equal to start time")

  def ordered(_), do: :ok

  def uint32(value, name, default, minimum \\ 1)
  def uint32(value, _name, default, _minimum) when value in [nil, ""], do: {:ok, default}

  def uint32(value, name, _default, minimum) when is_binary(value) and byte_size(value) <= 128 do
    case Integer.parse(value) do
      {n, ""} when n >= minimum and n <= 4_294_967_295 -> {:ok, n}
      {n, ""} when n < minimum and minimum == 1 -> error(name, "limit must be a positive value")
      {n, ""} -> error(name, "#{name} value #{n} is out of range [0, 4294967295]")
      _ -> error(name, "invalid #{name}")
    end
  end

  def uint32(_, name, _, _), do: error(name, "invalid #{name}")

  def direction(value) when value in [nil, ""], do: {:ok, :backward}

  def direction(value) when is_binary(value) and byte_size(value) <= 128 do
    case String.upcase(value) do
      "FORWARD" -> {:ok, :forward}
      "BACKWARD" -> {:ok, :backward}
      _ -> error("direction", "invalid direction '#{value}'")
    end
  end

  def direction(_), do: error("direction", "invalid direction")

  def default_step(start, finish), do: max(div(finish - start, 250 * @second), 1) * @second

  def step(value, start, finish) do
    with {:ok, step} <- duration(value, "step", default_step(start, finish)) do
      cond do
        step <= 0 ->
          error("step", "zero or negative query resolution step widths are not accepted. Try a positive integer")

        div(finish - start, step) > 11_000 ->
          error(
            "step",
            "exceeded maximum resolution of 11,000 points per time series. Try increasing the value of the step parameter"
          )

        true ->
          {:ok, step}
      end
    end
  end

  def interval(value) do
    case duration(value, "interval", 0) do
      {:ok, n} when n >= 0 -> {:ok, n}
      {:ok, _} -> error("interval", "interval must be >= 0")
      error -> error
    end
  end

  def since(value) when value in [nil, ""], do: {:ok, @hour}

  def since(value) when is_binary(value) and byte_size(value) <= 128 do
    case Quantity.duration_literal(value) do
      {:ok, n} -> {:ok, n}
      _ -> error("since", "could not parse 'since' parameter: invalid duration")
    end
  end

  def since(_), do: error("since", "could not parse 'since' parameter: invalid duration")

  def duration(value, name, default \\ nil)
  def duration(value, _name, default) when value in [nil, ""] and not is_nil(default), do: {:ok, default}

  def duration(value, name, _default) when is_binary(value) and byte_size(value) <= 128 do
    result =
      case FloatParser.parse(value) do
        {:ok, n} when is_float(n) and n >= @min / @second and n < @max / @second ->
          bounded(trunc(n * @second))

        _ ->
          Quantity.duration_literal(value)
      end

    case result do
      {:ok, n} -> {:ok, n}
      _ -> error(name, "cannot parse #{inspect(value)} to a valid duration")
    end
  end

  def duration(_, name, _), do: error(name, "invalid duration")

  def timestamp(value, default \\ nil, name \\ "time")
  def timestamp(value, default, _name) when value in [nil, ""], do: {:ok, default}
  def timestamp(value, default, name) when is_integer(value), do: timestamp(Integer.to_string(value), default, name)

  def timestamp(value, _default, name) when is_binary(value) and byte_size(value) <= 128 do
    result =
      if String.contains?(value, ".") do
        case FloatParser.parse(value) do
          {:ok, n} when is_float(n) and n >= @min / @second and n < @max / @second ->
            seconds = trunc(n)
            fraction = round((n - seconds) * 1000) / 1000
            bounded(seconds * @second + trunc(fraction * @second))

          _ ->
            integer_or_calendar(value)
        end
      else
        integer_or_calendar(value)
      end

    case result do
      {:ok, n} -> {:ok, n}
      _ -> error(name, "could not parse '#{name}' parameter: invalid timestamp")
    end
  end

  def timestamp(_, _, name), do: error(name, "could not parse '#{name}' parameter: invalid timestamp")

  defp integer_or_calendar(value) do
    case Integer.parse(value) do
      {n, ""} when n >= @min and n <= @max -> bounded(if(byte_size(value) <= 10, do: n * @second, else: n))
      _ -> calendar(value)
    end
  end

  defp calendar(value) do
    with [_, date, hour, minute, second, fraction, zone] <-
           Regex.run(
             ~r/\A(\d{4}-\d{2}-\d{2})T(\d{1,2}):(\d{2}):(\d{2})(?:[.,](\d+))?(Z|[+-]\d{2}:\d{2})\z/,
             value
           ),
         {:ok, date} <- Date.from_iso8601(date),
         {:ok, time} <- Time.new(String.to_integer(hour), String.to_integer(minute), String.to_integer(second)),
         {:ok, dt} <- DateTime.new(date, time),
         {:ok, offset} <- calendar_offset(zone) do
      nanos = fraction |> String.slice(0, 9) |> String.pad_trailing(9, "0") |> String.to_integer()
      bounded(DateTime.to_unix(dt, :nanosecond) + nanos - offset * @second)
    else
      _ -> :error
    end
  end

  defp calendar_offset("Z"), do: {:ok, 0}

  defp calendar_offset(<<sign, hour::binary-size(2), ?:, minute::binary-size(2)>>) do
    hour = String.to_integer(hour)
    minute = String.to_integer(minute)

    # Go's RFC3339 parser accepts these inclusive bounds, unlike ISO8601.
    if hour <= 24 and minute <= 60 do
      {:ok, (hour * 3600 + minute * 60) * if(sign == ?-, do: -1, else: 1)}
    else
      :error
    end
  end

  defp bounded(n) when n >= @min and n <= @max, do: {:ok, n}
  defp bounded(_), do: :error
  defp error(name, message), do: {:error, {:http_parameter_error, name, message}}
end
