defmodule Tuist.Pulse.Table do
  @moduledoc false
  @ranges %{"15m" => 900, "1h" => 3600, "6h" => 21_600, "24h" => 86_400}
  @sorts %{
    "metrics" => ~w(name value),
    "logs" => ~w(timestamp service level message trace_id),
    "traces" => ~w(timestamp service name duration_ms trace_id),
    "errors" => ~w(last_seen_ns first_seen_ns count title service project issue_id)
  }

  def validate(signal, params, mode \\ :table)

  def validate(signal, params, mode) when is_map(params) and is_map_key(@sorts, signal) do
    filters =
      case signal do
        "metrics" -> ~w(service)
        "logs" -> ~w(service level)
        "traces" -> ~w(service)
        "errors" -> ~w(project environment release service)
      end

    keys =
      ~w(range end_at page page_size) ++
        filters ++
        Enum.map(filters, &(&1 <> "_op")) ++ if(mode == :table, do: ~w(query search sort_by sort_order), else: [])

    query = Map.get(params, "query", Tuist.Pulse.default_query(signal))
    sort = Map.get(params, "sort_by", default_sort(signal))
    order = Map.get(params, "sort_order", if(signal == "metrics", do: "asc", else: "desc"))
    range = Map.get(params, "range", "1h")

    with true <- Enum.all?(Map.keys(params), &(&1 in keys)),
         true <- valid_text?(query) and (signal == "errors" or String.trim(query) != ""),
         true <- Enum.all?(filters ++ ["search"], &valid_text?(Map.get(params, &1, ""))),
         true <- Enum.all?(filters, &(Map.get(params, &1 <> "_op", "eq") in ~w(eq contains not_contains))),
         true <- sort in Map.fetch!(@sorts, signal) and order in ~w(asc desc),
         true <- is_binary(range) and Map.has_key?(@ranges, range),
         {:ok, page} <- integer(Map.get(params, "page", 1), 1, 2_147_483_647),
         {:ok, size} <- integer(Map.get(params, "page_size", 20), 1, 100),
         true <- not Map.has_key?(params, "end_at") or is_binary(params["end_at"]),
         {:ok, finish} <- finish(Map.get(params, "end_at", :now)),
         true <- DateTime.to_unix(finish) >= @ranges[range] and DateTime.to_unix(finish) <= 9_223_372_036 do
      {:ok,
       %{
         query: query,
         params: params,
         page: page,
         page_size: size,
         sort_by: sort,
         sort_order: order,
         finish: DateTime.to_unix(finish),
         seconds: @ranges[range],
         end_at: DateTime.to_iso8601(finish)
       }}
    else
      _ -> {:error, :invalid_params}
    end
  end

  def validate(_, _, _), do: {:error, :invalid_params}
  defp default_sort("metrics"), do: "name"
  defp default_sort("errors"), do: "last_seen_ns"
  defp default_sort(_), do: "timestamp"
  defp valid_text?(value), do: is_binary(value) and byte_size(value) <= 4096 and String.valid?(value)
  defp integer(value, min, max) when is_integer(value) and value >= min and value <= max, do: {:ok, value}

  defp integer(value, min, max) when is_binary(value) and byte_size(value) <= 10 do
    case Integer.parse(value) do
      {number, ""} -> integer(number, min, max)
      _ -> :error
    end
  end

  defp integer(_, _, _), do: :error
  defp finish(:now), do: {:ok, DateTime.truncate(DateTime.utc_now(), :second)}

  defp finish(value) when is_binary(value) and byte_size(value) <= 64 do
    case DateTime.from_iso8601(value) do
      {:ok, time, _} -> {:ok, DateTime.truncate(time, :second)}
      _ -> :error
    end
  end

  defp finish(_), do: :error

  def page(rows, opts) do
    rows = Enum.filter(rows, &matches?(&1, opts))
    {present, missing} = Enum.split_with(rows, &(not is_nil(sort_value(&1, opts.sort_by))))
    direction = if opts.sort_order == "asc", do: :asc, else: :desc
    rows = Enum.sort_by(present, &{sort_value(&1, opts.sort_by), tie(&1)}, direction) ++ Enum.sort_by(missing, &tie/1)
    count = length(rows)
    total_pages = ceil(count / opts.page_size)

    meta = %{
      "page" => opts.page,
      "page_size" => opts.page_size,
      "total_count" => count,
      "total_pages" => total_pages,
      "end_at" => opts.end_at,
      "has_next_page" => opts.page < total_pages,
      "has_previous_page" => opts.page > 1
    }

    {Enum.slice(rows, (opts.page - 1) * opts.page_size, opts.page_size), meta}
  end

  def filters?(row, params) do
    Enum.all?(~w(service level project environment release), fn key ->
      value = params[key]
      actual = row[key] || if(key == "service", do: get_in(row, ["labels", "service_name"])) || ""

      case Map.get(params, key <> "_op", "eq") do
        _ when value in [nil, ""] -> true
        "eq" -> actual == value
        "contains" -> String.contains?(String.downcase(actual), String.downcase(value))
        "not_contains" -> not String.contains?(String.downcase(actual), String.downcase(value))
      end
    end)
  end

  defp matches?(row, opts) do
    search = String.downcase(Map.get(opts.params, "search", ""))
    title = String.downcase(opts.query)

    filters?(row, opts.params) and String.contains?(String.downcase(Jason.encode!(row)), search) and
      (not Map.has_key?(row, "issue_id") or String.contains?(String.downcase(row["title"] || ""), title))
  end

  defp sort_value(row, key) when key in ~w(timestamp timestamp_ns first_seen_ns last_seen_ns) do
    case row[key] do
      value when is_binary(value) -> String.to_integer(value)
      value -> value
    end
  end

  defp sort_value(row, "value"), do: if(is_number(row["value"]), do: row["value"])
  defp sort_value(row, key), do: row[key]
  defp tie(row), do: :erlang.term_to_binary(row)
end
