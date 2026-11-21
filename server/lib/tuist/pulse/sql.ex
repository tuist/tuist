defmodule Tuist.Pulse.SQL do
  @moduledoc false

  # SQL is authored here, never supplied by a dashboard user. The database
  # credential is independently read-only. OTLP stores dotted resource keys
  # inside JSON, not as promoted service_name columns on the logs table.
  @distinct_events "count(DISTINCT event_id)"
  @log_service ~s|json_get_string(resource_attributes, '["service.name"]')|

  def query(signal, opts, request) do
    {table, columns, search} =
      case signal do
        "logs" ->
          {"opentelemetry_logs",
           "arrow_cast(timestamp, 'Int64') AS timestamp, #{@log_service} AS service, " <>
             "severity_text AS level, body AS message, trace_id", "body"}

        "traces" ->
          {"opentelemetry_traces",
           "arrow_cast(timestamp, 'Int64') AS timestamp, service_name AS service, span_name AS name, " <>
             "duration_nano / 1000000.0 AS duration_ms, trace_id", "span_name"}
      end

    predicate =
      if opts.query == "*",
        do: "",
        else: " AND strpos(lower(#{search}), lower(#{literal(opts.query)})) > 0"

    query = fn seconds ->
      "SELECT #{columns} FROM #{table} WHERE #{bounds(opts.finish - seconds, opts.finish)}#{predicate} " <>
        "ORDER BY timestamp DESC, trace_id ASC LIMIT 100"
    end

    with {:ok, rows} <- newest(request, query, opts.seconds),
         true <- Enum.all?(rows, &valid_row?(&1, signal)) do
      rows = Enum.map(rows, &Map.update!(&1, "timestamp", fn value -> Integer.to_string(value) end))
      {:ok, %{rows: rows, series: [], warnings: []}}
    else
      false -> {:error, :malformed_response}
      error -> error
    end
  end

  # A top 100 by time reads every row in its window, and Pulse ingests thousands
  # of spans per second, so the newest minute usually holds the whole page.
  # Narrower windows ending at the same instant are tried first: once one holds
  # 100 matches, every row of the full window's top 100 is newer than its start,
  # so the result is identical, ties included.
  defp newest(request, query, seconds) do
    windows = Enum.filter([60, 900], &(&1 < seconds)) ++ [seconds]

    Enum.reduce_while(windows, nil, fn window, _ ->
      case sql(request, query.(window)) do
        {:ok, rows} when length(rows) < 100 and window < seconds -> {:cont, nil}
        result -> {:halt, result}
      end
    end)
  end

  # One query computes every widget of a signal, so each window is scanned once
  # rather than once per widget. A widget's filter becomes an aggregate FILTER,
  # which Pulse pushes down with the partial aggregate to every region, so a
  # filtered expression must be a single aggregate call. Returns a map from
  # widget id to its value, or to its points in :range mode.
  def aggregate(signal, ids, mode, window, request) do
    {table, _expression, _filter} = aggregate_expression(signal, hd(ids))

    columns =
      Enum.map_join(ids, ", ", fn id ->
        {^table, expression, filter} = aggregate_expression(signal, id)
        filter = if filter, do: " FILTER (WHERE #{filter})", else: ""
        ~s|#{expression}#{filter} AS "#{id}"|
      end)

    predicate = bounds(window.start, window.finish)
    # Match (start, end] buckets. Count every span, not only root spans; duration
    # is returned in seconds because Pulse scales its millisecond widgets.
    bucket = "((arrow_cast(timestamp, 'Int64') - 1) / #{window.step * 1_000_000_000} + 1) * #{window.step}"

    query =
      if mode == :range do
        "SELECT #{bucket} AS bucket, #{columns} FROM #{table} WHERE #{predicate} GROUP BY bucket ORDER BY bucket"
      else
        "SELECT #{columns} FROM #{table} WHERE #{predicate}"
      end

    with {:ok, rows} <- sql(request, query),
         true <-
           Enum.all?(rows, fn row ->
             Enum.all?(ids, &(Map.has_key?(row, &1) and (is_nil(row[&1]) or is_number(row[&1]))))
           end) do
      aggregate_result(rows, mode, ids, window)
    else
      false -> {:error, :malformed_response}
      error -> error
    end
  end

  def counts?(signal, ids),
    do: Enum.all?(ids, &(elem(aggregate_expression(signal, &1), 1) in ["count(*)", @distinct_events]))

  # The buckets of a range partition its window exactly and a missing bucket is
  # a zero count, so a count's total is the sum of its buckets. One bucketed scan
  # of the previous and current periods therefore yields the chart and both
  # totals, rather than scanning the current period twice and the previous once.
  def periods(signal, ids, window, previous_window, request) do
    with {:ok, points, _} <- aggregate(signal, ids, :range, %{window | start: previous_window.start}, request),
         # A count is never null; a null bucket is a malformed response.
         true <- Enum.all?(points, fn {_, points} -> Enum.all?(points, &is_integer(List.last(&1))) end) do
      split = Map.new(points, fn {id, points} -> {id, Enum.split_with(points, &(hd(&1) <= window.start))} end)
      total = fn points -> points |> Enum.map(&List.last/1) |> Enum.sum() end

      {:ok, Map.new(split, fn {id, {_, current}} -> {id, total.(current)} end),
       Map.new(split, fn {id, {_, current}} -> {id, current} end),
       Map.new(split, fn {id, {previous, _}} -> {id, total.(previous)} end)}
    else
      false -> {:error, :malformed_response}
      error -> error
    end
  end

  defp aggregate_result(rows, :range, ids, window) do
    if Enum.all?(rows, &(is_integer(&1["bucket"]) and &1["bucket"] > window.start and &1["bucket"] <= window.finish)) do
      rows = Map.new(rows, &{&1["bucket"], &1})

      points =
        Map.new(ids, fn id ->
          empty = if id == "duration_p95", do: nil, else: 0

          {id,
           for(
             time <- (window.start + window.step)..window.finish//window.step,
             do: [time, Map.get(rows[time] || %{}, id, empty)]
           )}
        end)

      {:ok, points, []}
    else
      {:error, :malformed_response}
    end
  end

  defp aggregate_result(rows, _mode, ids, _window) do
    case rows do
      [row] -> {:ok, Map.take(row, ids), []}
      _ -> {:error, :malformed_response}
    end
  end

  defp aggregate_expression("logs", "entries"), do: {"opentelemetry_logs", "count(*)", nil}

  defp aggregate_expression("logs", "errors"),
    do: {"opentelemetry_logs", "count(*)", "upper(severity_text) IN ('ERROR', 'FATAL')"}

  defp aggregate_expression("logs", "warnings"),
    do: {"opentelemetry_logs", "count(*)", "upper(severity_text) IN ('WARN', 'WARNING')"}

  defp aggregate_expression("traces", "spans"), do: {"opentelemetry_traces", "count(*)", nil}

  defp aggregate_expression("traces", "errors"),
    do: {"opentelemetry_traces", "count(*)", "span_status_code = 'STATUS_CODE_ERROR'"}

  defp aggregate_expression("traces", "duration_p95"),
    do: {"opentelemetry_traces", "approx_percentile_cont(duration_nano, 0.95) / 1000000000.0", nil}

  # `errors` keeps an SDK's resends as rows with the same event ID and
  # timestamp, so they always share a bucket and these counts still add up.
  defp aggregate_expression("errors", "events"), do: {"errors", @distinct_events, nil}
  defp aggregate_expression("errors", "fatal"), do: {"errors", @distinct_events, ~s|"level" = 'fatal'|}
  defp aggregate_expression("errors", "services"), do: {"errors", "count(DISTINCT nullif(service, ''))", nil}

  def bounds(start, finish),
    do: "timestamp > to_timestamp_seconds(#{start}) AND timestamp <= to_timestamp_seconds(#{finish})"

  # Pulse's SQL treats backslashes literally; doubling quotes is the only escape.
  def literal(value), do: "'" <> String.replace(value, "'", "''") <> "'"

  def sql(request, query) do
    with {:ok, %{"output" => [%{"records" => %{"schema" => %{"column_schemas" => columns}, "rows" => rows}}]}} <-
           request.(sql: query),
         true <- is_list(columns) and is_list(rows),
         true <- Enum.all?(columns, &is_binary(&1["name"])),
         true <- Enum.all?(rows, &(is_list(&1) and length(&1) == length(columns))) do
      names = Enum.map(columns, & &1["name"])
      {:ok, Enum.map(rows, &Map.new(Enum.zip(names, &1)))}
    else
      {:error, _} = error -> error
      _ -> {:error, :malformed_response}
    end
  end

  defp valid_row?(row, signal) do
    fields = if signal == "logs", do: ~w(service level message trace_id), else: ~w(service name trace_id)

    is_integer(row["timestamp"]) and row["timestamp"] >= 0 and
      Enum.all?(fields, &(is_binary(row[&1]) or is_nil(row[&1]))) and
      (signal == "logs" or is_nil(row["duration_ms"]) or is_number(row["duration_ms"]))
  end
end
