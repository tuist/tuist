defmodule Tuist.Pulse.Explore do
  @moduledoc """
  Validation and SQL for agent-facing Pulse exploration: label discovery,
  structured log and span search, and trace lookup. `Tuist.Pulse.explore/4`
  authorizes the caller and supplies the read-only transport.

  Callers never supply SQL. Their text reaches SQL only as escaped string
  literals. A trace label becomes a column only when it names one of Pulse's
  own trace columns; a log label is either a fixed log column or a JSON
  attribute key addressed through a literal path. Every read is bounded by a
  window of at most 24 hours ending at `end_at` and by a row limit, in
  addition to the transport's body-size and timeout limits.

  Log labels are the optional log columns the table has (the Loki pipeline
  omits `span_id` and `scope_name`) and the keys of each entry's resource
  attributes (Loki stream labels such as `namespace` or `container`) and log
  attributes (structured metadata such as `pod`); a key present in both
  resolves to the resource attribute. Log label discovery returns only keys
  that filters accept and inspects at most 1000 distinct attribute sets of each
  kind in the window.
  """

  alias Tuist.Pulse.SQL

  @ranges %{"15m" => 900, "1h" => 3600, "6h" => 21_600, "24h" => 86_400}
  @ops ~w(eq neq contains not_contains)
  @log_columns ~w(severity_text scope_name trace_id span_id)
  @label ~r/\A[A-Za-z0-9_][A-Za-z0-9_.\-\/]{0,254}\z/
  @metric_label ~r/\A[A-Za-z_][A-Za-z0-9_]{0,127}\z/
  @trace_id ~r/\A[0-9a-f]{1,64}\z/
  @attribute_sets 1000
  @spans 1000
  @keys %{
    metrics: ~w(query type range end_at step),
    labels: ~w(signal label match filters search range end_at limit),
    logs: ~w(text filters range end_at limit order),
    traces: ~w(filters min_duration_ms max_duration_ms root_only range end_at limit order),
    trace: ~w(trace_id range end_at)
  }
  @span_fields ~w(trace_id span_id parent_span_id service_name span_name span_kind span_status_code span_status_message scope_name)

  def validate(operation, params) when is_map_key(@keys, operation) and is_map(params) do
    with true <- Enum.all?(Map.keys(params), &(&1 in @keys[operation])),
         {:ok, window} <- window(params, if(operation == :trace, do: "24h", else: "1h")),
         {:ok, options} <- options(operation, params, window) do
      {:ok, Map.merge(window, options)}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_params}
    end
  end

  def validate(_operation, _params), do: {:error, :invalid_params}

  defp window(params, default) do
    range = Map.get(params, "range", default)

    with true <- is_binary(range) and Map.has_key?(@ranges, range),
         {:ok, finish} <- finish(Map.get(params, "end_at")),
         seconds = @ranges[range],
         true <- finish >= seconds and finish <= 9_223_372_036 do
      {:ok,
       %{
         start: finish - seconds,
         finish: finish,
         seconds: seconds,
         start_at: iso8601(finish - seconds),
         end_at: iso8601(finish)
       }}
    else
      _ -> {:error, :invalid_params}
    end
  end

  defp finish(nil), do: {:ok, DateTime.to_unix(DateTime.utc_now())}

  defp finish(value) when is_binary(value) and byte_size(value) <= 64 do
    case DateTime.from_iso8601(value) do
      {:ok, time, _} -> {:ok, DateTime.to_unix(time)}
      _ -> :error
    end
  end

  defp finish(_value), do: :error

  defp iso8601(seconds), do: seconds |> DateTime.from_unix!() |> DateTime.to_iso8601()

  defp options(:metrics, params, window) do
    query = params["query"]
    min_step = max(1, ceil(window.seconds / 360))

    if text?(query, 4096) and String.trim(query) != "" do
      case Map.get(params, "type", "instant") do
        "instant" ->
          if Map.has_key?(params, "range") or Map.has_key?(params, "step"),
            do: {:error, :instant_window},
            else: {:ok, %{query: query, type: "instant", step: nil, start_at: iso8601(window.finish)}}

        "range" ->
          with {:ok, step} <- integer(Map.get(params, "step", min_step), min_step, window.seconds),
               do: {:ok, %{query: query, type: "range", step: step}}

        _ ->
          :error
      end
    end
  end

  defp options(:labels, params, _window) do
    signal = params["signal"]
    label = params["label"]
    match = params["match"]

    with true <- signal in ~w(metrics logs traces),
         true <- is_nil(label) or (is_binary(label) and Regex.match?(label_pattern(signal), label)),
         true <- is_nil(match) or (signal == "metrics" and text?(match, 4096) and String.trim(match) != ""),
         true <- signal != "metrics" or not Map.has_key?(params, "filters"),
         # Trace label names come from the schema, so there are no entries to filter.
         true <- not (signal == "traces" and is_nil(label) and Map.has_key?(params, "filters")),
         true <- text?(Map.get(params, "search", ""), 256),
         {:ok, filters} <- filters(params["filters"]),
         {:ok, limit} <- integer(Map.get(params, "limit", 100), 1, 1000),
         :ok <- metric_selector(signal, label, match) do
      {:ok,
       %{
         signal: signal,
         label: label,
         match: match,
         filters: filters,
         search: Map.get(params, "search", ""),
         limit: limit
       }}
    end
  end

  defp options(:logs, params, _window) do
    with true <- text?(Map.get(params, "text", ""), 4096),
         {:ok, filters} <- filters(params["filters"]),
         {:ok, limit} <- integer(Map.get(params, "limit", 50), 1, 100),
         order when order in ~w(newest oldest) <- Map.get(params, "order", "newest") do
      {:ok, %{text: Map.get(params, "text", ""), filters: filters, limit: limit, order: order}}
    end
  end

  defp options(:traces, params, _window) do
    with {:ok, filters} <- filters(params["filters"]),
         {:ok, min} <- duration(params["min_duration_ms"]),
         {:ok, max} <- duration(params["max_duration_ms"]),
         root_only when is_boolean(root_only) <- Map.get(params, "root_only", false),
         {:ok, limit} <- integer(Map.get(params, "limit", 50), 1, 100),
         order when order in ~w(newest oldest slowest) <- Map.get(params, "order", "newest") do
      {:ok, %{filters: filters, min: min, max: max, root_only: root_only, limit: limit, order: order}}
    end
  end

  defp options(:trace, params, _window) do
    trace_id = params["trace_id"]

    if is_binary(trace_id) and Regex.match?(@trace_id, String.downcase(trace_id)),
      do: {:ok, %{trace_id: String.downcase(trace_id)}},
      else: :error
  end

  # Pulse answers metric label values only for a series selector, except metric names.
  defp metric_selector("metrics", label, nil) when label not in [nil, "__name__"], do: {:error, :match_required}
  defp metric_selector(_signal, _label, _match), do: :ok

  defp label_pattern("metrics"), do: @metric_label
  defp label_pattern(_signal), do: @label

  defp filters(nil), do: {:ok, []}

  defp filters(filters) when is_list(filters) and length(filters) <= 10 do
    filters
    |> Enum.reduce_while({:ok, []}, fn
      %{"label" => label, "value" => value} = filter, {:ok, acc} ->
        op = Map.get(filter, "op", "eq")

        if Enum.all?(Map.keys(filter), &(&1 in ~w(label op value))) and is_binary(label) and
             Regex.match?(@label, label) and op in @ops and text?(value, 4096),
           do: {:cont, {:ok, [%{label: label, op: op, value: value} | acc]}},
           else: {:halt, :error}

      _, _ ->
        {:halt, :error}
    end)
    |> case do
      {:ok, filters} -> {:ok, Enum.reverse(filters)}
      error -> error
    end
  end

  defp filters(_filters), do: :error

  defp duration(nil), do: {:ok, nil}
  defp duration(value) when is_number(value) and value >= 0 and value <= 86_400_000, do: {:ok, round(value * 1_000_000)}
  defp duration(_value), do: :error

  defp integer(value, min, max) when is_integer(value) and value >= min and value <= max, do: {:ok, value}
  defp integer(_value, _min, _max), do: :error

  defp text?(value, max),
    do: is_binary(value) and byte_size(value) <= max and String.valid?(value) and not String.contains?(value, <<0>>)

  @doc """
  Runs a validated non-metric operation. `request` takes a Pulse API path and
  query parameters, so the same function reaches both the Prometheus API and SQL.
  """
  def run(:labels, %{signal: "metrics"} = opts, request) do
    {path, params} =
      if opts.label,
        do: {"/api/v1/label/#{opts.label}/values", [start: opts.start, end: opts.finish]},
        else: {"/api/v1/labels", [start: opts.start, end: opts.finish]}

    params = if opts.match, do: [{"match[]", opts.match} | params], else: params

    with {:ok, %{"status" => "success", "data" => data} = body} when is_list(data) <- request.(path, params),
         true <- Enum.all?(data, &is_binary/1),
         {:ok, warnings} <- warnings(body) do
      data
      |> Enum.filter(&contains?(&1, opts.search))
      |> Enum.sort()
      |> Enum.map(&%{value: &1, count: nil})
      |> labels_result(opts, false, warnings)
    else
      {:error, _} = error -> error
      _ -> {:error, :malformed_response}
    end
  end

  def run(:labels, %{signal: "logs", label: nil} = opts, request) do
    with {:ok, columns} <- log_columns(request) do
      log_label_names(opts, columns, request)
    end
  end

  def run(:labels, %{signal: "traces", label: nil} = opts, request) do
    with {:ok, columns} <- trace_columns(request) do
      columns
      |> Enum.reject(fn {_name, type} -> type in ["json"] or String.starts_with?(type, "timestamp") end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.filter(&contains?(&1, opts.search))
      |> Enum.sort()
      |> Enum.map(&%{value: &1, count: nil})
      |> labels_result(opts, false, [])
    end
  end

  def run(:labels, %{signal: signal} = opts, request) do
    with {:ok, table, expression, predicates} <- label_query(signal, opts, request) do
      search =
        if opts.search == "",
          do: "",
          else: " AND strpos(lower(#{expression}), lower(#{SQL.literal(opts.search)})) > 0"

      sql =
        "SELECT #{expression} AS value, count(*) AS count FROM #{table} " <>
          "WHERE #{SQL.bounds(opts.start, opts.finish)}#{predicates}#{search} " <>
          "GROUP BY value ORDER BY count DESC, value ASC LIMIT #{opts.limit + 1}"

      with {:ok, rows} <- sql(request, sql),
           true <- Enum.all?(rows, &((is_binary(&1["value"]) or is_nil(&1["value"])) and is_integer(&1["count"]))) do
        rows
        |> Enum.map(&%{value: &1["value"], count: &1["count"]})
        |> labels_result(opts, false, [])
      else
        false -> {:error, :malformed_response}
        error -> error
      end
    end
  end

  def run(:logs, opts, request) do
    text =
      if opts.text == "", do: "", else: " AND strpos(lower(body), lower(#{SQL.literal(opts.text)})) > 0"

    direction = if opts.order == "oldest", do: "ASC", else: "DESC"

    with {:ok, columns} <- log_columns(request),
         sql =
           "SELECT arrow_cast(timestamp, 'Int64') AS timestamp, body, #{Enum.map_join(columns, &(&1 <> ", "))}" <>
             "json_to_string(resource_attributes) AS resource_attributes, json_to_string(log_attributes) AS log_attributes " <>
             "FROM opentelemetry_logs WHERE #{SQL.bounds(opts.start, opts.finish)}" <>
             "#{log_predicates(opts.filters, columns)}#{text} ORDER BY timestamp #{direction} LIMIT #{opts.limit + 1}",
         {:ok, rows} <- sql(request, sql),
         true <- Enum.all?(rows, &valid_log?/1) do
      rows =
        Enum.map(rows, fn row ->
          # Resource attributes win, matching the label filters' coalesce order.
          attributes =
            Map.merge(decode_attributes(row["log_attributes"]), decode_attributes(row["resource_attributes"]))

          # A column the table lacks is null, like an absent value.
          ["body" | @log_columns]
          |> Map.new(&{&1, row[&1]})
          |> Map.merge(%{"timestamp" => Integer.to_string(row["timestamp"]), "attributes" => attributes})
        end)

      {:ok, rows_result(rows, opts)}
    else
      false -> {:error, :malformed_response}
      error -> error
    end
  end

  def run(:traces, opts, request) do
    with {:ok, predicates} <- trace_predicates(opts.filters, request) do
      predicates =
        predicates <>
          if(opts.min, do: " AND duration_nano >= #{opts.min}", else: "") <>
          if(opts.max, do: " AND duration_nano <= #{opts.max}", else: "") <>
          if(opts.root_only, do: " AND (parent_span_id IS NULL OR parent_span_id = '')", else: "")

      order =
        case opts.order do
          "newest" -> "timestamp DESC, span_id ASC"
          "oldest" -> "timestamp ASC, span_id ASC"
          "slowest" -> "duration_nano DESC, timestamp DESC, span_id ASC"
        end

      sql =
        "SELECT arrow_cast(timestamp, 'Int64') AS timestamp, #{Enum.join(@span_fields, ", ")}, " <>
          "duration_nano / 1000000.0 AS duration_ms FROM opentelemetry_traces " <>
          "WHERE #{SQL.bounds(opts.start, opts.finish)}#{predicates} ORDER BY #{order} LIMIT #{opts.limit + 1}"

      with {:ok, rows} <- sql(request, sql),
           true <- Enum.all?(rows, &valid_span?/1) do
        rows = Enum.map(rows, &Map.update!(&1, "timestamp", fn value -> Integer.to_string(value) end))
        {:ok, rows_result(rows, opts)}
      else
        false -> {:error, :malformed_response}
        error -> error
      end
    end
  end

  def run(:trace, opts, request) do
    with {:ok, columns} <- trace_columns(request) do
      select =
        Enum.map_join(columns, ", ", fn {name, type} ->
          cond do
            String.starts_with?(type, "timestamp") -> ~s|arrow_cast("#{name}", 'Int64') AS "#{name}"|
            type == "json" -> ~s|json_to_string("#{name}") AS "#{name}"|
            true -> ~s|"#{name}"|
          end
        end)

      sql =
        "SELECT #{select} FROM opentelemetry_traces WHERE #{SQL.bounds(opts.start, opts.finish)} " <>
          "AND trace_id = #{SQL.literal(opts.trace_id)} ORDER BY timestamp ASC, span_id ASC LIMIT #{@spans + 1}"

      with {:ok, rows} <- sql(request, sql),
           true <- Enum.all?(rows, &(is_integer(&1["timestamp"]) and &1["timestamp"] >= 0)) do
        types = Map.new(columns)

        {spans, resources} = rows |> Enum.take(@spans) |> Enum.map(&span(&1, types)) |> index_resources()

        {:ok,
         %{
           trace_id: opts.trace_id,
           spans: spans,
           resources: resources,
           truncated: length(rows) > @spans,
           start_at: opts.start_at,
           end_at: opts.end_at
         }}
      else
        false -> {:error, :malformed_response}
        error -> error
      end
    end
  end

  defp log_label_names(opts, columns, request) do
    where = SQL.bounds(opts.start, opts.finish) <> log_predicates(opts.filters, columns)

    ["resource_attributes", "log_attributes"]
    |> Enum.reduce_while({:ok, MapSet.new(columns), false}, fn column, {:ok, names, truncated} ->
      sql =
        "SELECT json_to_string(#{column}) AS attributes FROM opentelemetry_logs WHERE #{where} " <>
          "GROUP BY attributes LIMIT #{@attribute_sets + 1}"

      case sql(request, sql) do
        {:ok, rows} ->
          keys =
            rows
            |> Enum.flat_map(&(&1["attributes"] |> decode_attributes() |> Map.keys()))
            |> Enum.filter(&Regex.match?(@label, &1))

          {:cont, {:ok, MapSet.union(names, MapSet.new(keys)), truncated or length(rows) > @attribute_sets}}

        error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, names, truncated} ->
        names
        |> Enum.filter(&contains?(&1, opts.search))
        |> Enum.sort()
        |> Enum.map(&%{value: &1, count: nil})
        |> labels_result(opts, truncated, [])

      error ->
        error
    end
  end

  # Spans from one process repeat the same resource attributes; list each set once.
  defp index_resources(spans) do
    Enum.map_reduce(spans, [], fn {span, resource}, resources ->
      case Enum.find_index(resources, &(&1 == resource)) do
        nil -> {Map.put(span, "resource", length(resources)), resources ++ [resource]}
        index -> {Map.put(span, "resource", index), resources}
      end
    end)
  end

  defp span(row, types) do
    {fields, attributes} =
      Map.split(row, @span_fields ++ ~w(timestamp timestamp_end duration_nano span_events span_links))

    {resource, attributes} =
      attributes
      |> Enum.reject(fn {_name, value} -> value in [nil, ""] end)
      |> Map.new(fn {name, value} ->
        {name, if(types[name] == "json" or not scalar?(value), do: to_string_value(value), else: value)}
      end)
      |> Map.split_with(fn {name, _value} -> String.starts_with?(name, "resource_attributes.") end)

    # Every core field is present, null when Pulse's schema lacks the column.
    span =
      @span_fields
      |> Map.new(&{&1, fields[&1]})
      |> Map.merge(%{
        "timestamp" => Integer.to_string(fields["timestamp"]),
        "timestamp_end" => if(is_integer(fields["timestamp_end"]), do: Integer.to_string(fields["timestamp_end"])),
        "duration_ms" => if(is_number(fields["duration_nano"]), do: fields["duration_nano"] / 1_000_000),
        "events" => decode_list(fields["span_events"]),
        "links" => decode_list(fields["span_links"]),
        "attributes" => attributes
      })

    {span, resource}
  end

  defp label_query("logs", opts, request) do
    with {:ok, columns} <- log_columns(request),
         do: {:ok, "opentelemetry_logs", log_expression(opts.label, columns), log_predicates(opts.filters, columns)}
  end

  defp label_query("traces", opts, request) do
    with {:ok, columns} <- trace_columns(request),
         {:ok, expression} <- trace_expression(opts.label, Map.new(columns)),
         {:ok, predicates} <- trace_predicates(opts.filters, columns) do
      {:ok, "opentelemetry_traces", expression, predicates}
    end
  end

  defp log_expression(label, columns) do
    if label in columns, do: label, else: attribute_expression(label)
  end

  defp attribute_expression(label) do
    path = SQL.literal(~s|["#{label}"]|)
    "coalesce(json_get_string(resource_attributes, #{path}), json_get_string(log_attributes, #{path}))"
  end

  defp log_predicates(filters, columns), do: Enum.map_join(filters, &predicate(log_expression(&1.label, columns), &1))

  defp trace_predicates([], _request_or_columns), do: {:ok, ""}

  defp trace_predicates(filters, request) when is_function(request) do
    with {:ok, columns} <- trace_columns(request), do: trace_predicates(filters, columns)
  end

  defp trace_predicates(filters, columns) when is_list(columns) do
    types = Map.new(columns)

    Enum.reduce_while(filters, {:ok, ""}, fn filter, {:ok, acc} ->
      case trace_expression(filter.label, types) do
        {:ok, expression} -> {:cont, {:ok, acc <> predicate(expression, filter)}}
        error -> {:halt, error}
      end
    end)
  end

  # Only labels that name one of Pulse's own scalar trace columns become identifiers.
  defp trace_expression(label, types) do
    case types[label] do
      nil -> {:error, :unknown_label}
      "json" -> {:error, :unknown_label}
      "string" -> {:ok, ~s|"#{label}"|}
      "timestamp" <> _ -> {:error, :unknown_label}
      _ -> {:ok, ~s|CAST("#{label}" AS STRING)|}
    end
  end

  # The Loki pipeline creates the logs table without the OTLP-only columns
  # (span_id, scope_name), so the optional log columns are discovered too.
  defp log_columns(request) do
    with {:ok, columns} <- columns(request, "opentelemetry_logs"),
         do: {:ok, Enum.filter(@log_columns, &List.keymember?(columns, &1, 0))}
  end

  defp trace_columns(request), do: columns(request, "opentelemetry_traces")

  defp columns(request, table) do
    sql =
      "SELECT column_name, data_type FROM information_schema.columns " <>
        "WHERE table_schema = database() AND table_name = #{SQL.literal(table)}"

    with {:ok, rows} <- sql(request, sql),
         true <- rows != [] and Enum.all?(rows, &(is_binary(&1["column_name"]) and is_binary(&1["data_type"]))) do
      {:ok,
       rows
       # Attribute keys from instrumented apps become columns; only safe names are quoted.
       |> Enum.filter(&Regex.match?(@label, &1["column_name"]))
       |> Enum.map(&{&1["column_name"], String.downcase(&1["data_type"])})}
    else
      false -> {:error, :malformed_response}
      error -> error
    end
  end

  defp sql(request, query), do: SQL.sql(&request.("/v1/sql", &1), query)

  defp predicate(expression, %{op: op, value: value}) do
    literal = SQL.literal(value)

    case op do
      "eq" -> " AND #{expression} = #{literal}"
      "neq" -> " AND (#{expression} IS NULL OR #{expression} <> #{literal})"
      "contains" -> " AND strpos(lower(#{expression}), lower(#{literal})) > 0"
      "not_contains" -> " AND (#{expression} IS NULL OR strpos(lower(#{expression}), lower(#{literal})) = 0)"
    end
  end

  defp labels_result(values, opts, truncated, warnings) do
    {:ok,
     %{
       label: opts.label,
       values: Enum.take(values, opts.limit),
       truncated: truncated or length(values) > opts.limit,
       start_at: opts.start_at,
       end_at: opts.end_at,
       warnings: warnings
     }}
  end

  defp rows_result(rows, opts),
    do: %{
      rows: Enum.take(rows, opts.limit),
      truncated: length(rows) > opts.limit,
      start_at: opts.start_at,
      end_at: opts.end_at
    }

  defp valid_log?(row) do
    is_integer(row["timestamp"]) and row["timestamp"] >= 0 and
      Enum.all?(
        ~w(severity_text body trace_id span_id scope_name resource_attributes log_attributes),
        &(is_binary(row[&1]) or is_nil(row[&1]))
      )
  end

  defp valid_span?(row) do
    is_integer(row["timestamp"]) and row["timestamp"] >= 0 and
      Enum.all?(@span_fields, &(is_binary(row[&1]) or is_nil(row[&1]))) and
      (is_nil(row["duration_ms"]) or is_number(row["duration_ms"]))
  end

  defp decode_attributes(value) when is_binary(value) do
    case JSON.decode(value) do
      {:ok, %{} = attributes} -> Map.new(attributes, fn {key, value} -> {key, to_string_value(value)} end)
      _ -> %{}
    end
  end

  defp decode_attributes(_value), do: %{}

  defp decode_list(value) when is_binary(value) do
    case JSON.decode(value) do
      {:ok, list} when is_list(list) -> list
      _ -> []
    end
  end

  defp decode_list(_value), do: []

  defp scalar?(value), do: is_binary(value) or is_number(value) or is_boolean(value)
  defp to_string_value(value) when is_binary(value), do: value
  defp to_string_value(value), do: JSON.encode!(value)

  defp contains?(_value, ""), do: true
  defp contains?(value, search), do: String.contains?(String.downcase(value), String.downcase(search))

  defp warnings(body) do
    case Map.get(body, "warnings", []) do
      warnings when is_list(warnings) ->
        if Enum.all?(warnings, &is_binary/1), do: {:ok, Enum.take(warnings, 100)}, else: {:error, :malformed_response}

      _ ->
        {:error, :malformed_response}
    end
  end
end
