defmodule Tuist.Pulse.SQL do
  @moduledoc false

  # SQL is authored here, never supplied by a dashboard user. The database
  # credential is independently read-only. OTLP stores dotted resource keys
  # inside JSON, not as promoted service_name columns on the logs table.
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

    sql =
      "SELECT #{columns} FROM #{table} WHERE #{bounds(opts.finish - opts.seconds, opts.finish)}#{predicate} " <>
        "ORDER BY timestamp DESC, trace_id ASC LIMIT 100"

    with {:ok, rows} <- sql(request, sql),
         true <- Enum.all?(rows, &valid_row?(&1, signal)) do
      rows = Enum.map(rows, &Map.update!(&1, "timestamp", fn value -> Integer.to_string(value) end))
      {:ok, %{rows: rows, series: [], warnings: []}}
    else
      false -> {:error, :malformed_response}
      error -> error
    end
  end

  def aggregate(signal, id, mode, window, request) do
    {table, expression, filter} = aggregate_expression(signal, id)
    predicate = bounds(window.start, window.finish) <> filter
    # Match (start, end] buckets. Count every span, not only root spans; duration
    # is returned in seconds because Pulse scales its millisecond widgets.
    bucket = "((arrow_cast(timestamp, 'Int64') - 1) / #{window.step * 1_000_000_000} + 1) * #{window.step}"

    query =
      if mode == :range do
        "SELECT #{bucket} AS bucket, #{expression} AS value FROM #{table} WHERE #{predicate} GROUP BY bucket ORDER BY bucket"
      else
        "SELECT #{expression} AS value FROM #{table} WHERE #{predicate}"
      end

    with {:ok, rows} <- sql(request, query),
         true <- Enum.all?(rows, &(is_nil(&1["value"]) or is_number(&1["value"]))) do
      aggregate_result(rows, mode, id, window)
    else
      false -> {:error, :malformed_response}
      error -> error
    end
  end

  defp aggregate_result(rows, :range, id, window) do
    if Enum.all?(rows, &(is_integer(&1["bucket"]) and &1["bucket"] > window.start and &1["bucket"] <= window.finish)) do
      values = Map.new(rows, &{&1["bucket"], &1["value"]})
      empty = if id == "duration_p95", do: nil, else: 0

      points =
        for time <- (window.start + window.step)..window.finish//window.step, do: [time, Map.get(values, time, empty)]

      {:ok, points, []}
    else
      {:error, :malformed_response}
    end
  end

  defp aggregate_result(rows, _mode, _id, _window) do
    case rows do
      [%{"value" => value}] -> {:ok, value, []}
      _ -> {:error, :malformed_response}
    end
  end

  defp aggregate_expression("logs", "entries"), do: {"opentelemetry_logs", "count(*)", ""}

  defp aggregate_expression("logs", "errors"),
    do: {"opentelemetry_logs", "count(*)", " AND upper(severity_text) IN ('ERROR', 'FATAL')"}

  defp aggregate_expression("logs", "warnings"),
    do: {"opentelemetry_logs", "count(*)", " AND upper(severity_text) IN ('WARN', 'WARNING')"}

  defp aggregate_expression("traces", "spans"), do: {"opentelemetry_traces", "count(*)", ""}

  defp aggregate_expression("traces", "errors"),
    do: {"opentelemetry_traces", "count(*)", " AND span_status_code = 'STATUS_CODE_ERROR'"}

  defp aggregate_expression("traces", "duration_p95"),
    do: {"opentelemetry_traces", "approx_percentile_cont(duration_nano, 0.95) / 1000000000.0", ""}

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
