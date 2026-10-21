defmodule Tuist.BuildEntities.Params do
  @moduledoc false

  def parse(params, now \\ DateTime.utc_now()) do
    with {:ok, start_at} <- timestamp(value(params, :start_at), DateTime.add(now, -30, :day)),
         {:ok, end_at} <- timestamp(value(params, :end_at), now),
         true <- DateTime.before?(start_at, end_at),
         true <- DateTime.compare(start_at, DateTime.add(now, -90, :day)) != :lt,
         true <- DateTime.compare(end_at, now) != :gt,
         true <- valid_cursors?(value(params, :after), value(params, :before)),
         {:ok, page} <- integer(value(params, :page), 1, 1, 10_000),
         {:ok, page_size} <- integer(value(params, :page_size), 20, 1, 100),
         environment when environment in [nil, "any", "ci", "local"] <- value(params, :environment) do
      {:ok,
       [
         start_datetime: start_at,
         end_datetime: end_at,
         environment: environment || "any",
         branch: value(params, :branch),
         search: value(params, :q) || "",
         page: page,
         page_size: page_size,
         after: value(params, :after),
         before: value(params, :before)
       ]}
    else
      _ -> {:error, "Use a valid time range within the last 90 days, environment, and pagination."}
    end
  end

  defp valid_cursors?(after_cursor, before_cursor) do
    not (after_cursor not in [nil, ""] and before_cursor not in [nil, ""]) &&
      valid_cursor?(after_cursor) && valid_cursor?(before_cursor)
  end

  defp valid_cursor?(cursor) when cursor in [nil, ""], do: true

  defp valid_cursor?(cursor) when is_binary(cursor) and byte_size(cursor) <= 512 do
    with {:ok, decoded} <- Base.url_decode64(cursor, padding: false),
         [time, id] <- String.split(decoded, ":", parts: 2),
         {microseconds, ""} <- Integer.parse(time),
         {:ok, _} <- DateTime.from_unix(microseconds, :microsecond),
         {:ok, _} <- Ecto.UUID.cast(id) do
      true
    else
      _ -> false
    end
  end

  defp valid_cursor?(_), do: false

  defp value(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))

  defp timestamp(nil, default), do: {:ok, default}
  defp timestamp(%DateTime{} = value, _default), do: {:ok, value}

  defp timestamp(value, _default) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _ -> :error
    end
  end

  defp timestamp(_value, _default), do: :error

  defp integer(nil, default, _minimum, _maximum), do: {:ok, default}

  defp integer(value, _default, minimum, maximum) when is_integer(value) and value >= minimum and value <= maximum,
    do: {:ok, value}

  defp integer(value, default, minimum, maximum) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> integer(number, default, minimum, maximum)
      _ -> :error
    end
  end

  defp integer(_value, _default, _minimum, _maximum), do: :error
end
