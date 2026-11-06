defmodule PulseWeb.TempoController do
  @moduledoc "Tempo v1/v2 exact-ID trace lookup. Unsupported shard/partial modes fail closed."
  use PulseWeb, :controller

  alias Pulse.Auth
  alias Pulse.OTLP.Traces
  alias Pulse.PromQL.Parser
  alias Pulse.Traces.Metrics
  alias Pulse.Traces.SearchExpression
  alias Pulse.Traces.Tempo
  alias Pulse.Traces.TempoDiscovery
  alias Pulse.Traces.TempoDuration
  alias Pulse.Traces.TempoFilter
  alias Pulse.Traces.TempoIntrinsics
  alias Pulse.Traces.TempoSearch

  @conflicts [
    :trace_metadata_unknown,
    :trace_span_id_conflict,
    :trace_root_conflict,
    :trace_root_unknown,
    :trace_timestamp_unknown
  ]

  def tags(conn, params), do: discover(conn, params, 1, :names)
  def tags_v2(conn, params), do: discover(conn, params, 2, :names)
  def tag_values(conn, params), do: discover_path(conn, params, 1)
  def tag_values_v2(conn, params), do: discover_path(conn, params, 2)

  # A tag can contain slashes, including a literal /values inside its name.
  # Phoenix has already URL-decoded each segment; never decode the joined key again.
  defp discover_path(conn, %{"tag_path" => path} = params, version) do
    case Enum.split(path, -1) do
      {[_ | _] = name, ["values"]} ->
        params = params |> Map.delete("tag_path") |> Map.put("tag_name", Enum.join(name, "/"))
        discover(conn, params, version, :values)

      _ ->
        send_resp(conn, 404, "")
    end
  end

  defp discover(conn, params, version, mode) do
    with {:ok, tenant} <- tenant(conn),
         :ok <- authorize(conn, tenant),
         {:ok, scope, key} <- discovery_params(params, mode, version),
         {:ok, limit} <- discovery_limit(params, mode),
         {:ok, window} <- discovery_window(params),
         {:ok, format} <- format(conn),
         {:ok, body} <- TempoDiscovery.query(tenant, scope, key, version, format, params["q"], window, limit) do
      type = if format == "protobuf", do: "application/protobuf", else: "application/json"

      conn
      |> put_resp_content_type(type)
      |> put_resp_header("x-pulse-trace-coverage", discovery_coverage(scope, mode, params["q"], version, key))
      |> put_resp_header("x-pulse-trace-discovery-window", window_coverage(scope, key, window))
      |> put_resp_header(
        "x-pulse-trace-discovery-limit",
        if(limit == 0, do: "unlimited-within-safety-budgets", else: Integer.to_string(limit))
      )
      |> send_resp(200, body)
    else
      {:error, reason} -> failure(conn, reason)
    end
  end

  defp discovery_coverage("intrinsic", _mode, _query, _version, "trace:duration"),
    do: "complete-retained-trace-duration; exporter-completeness-unknown"

  defp discovery_coverage("intrinsic", _mode, _query, _version, key)
       when key in ~w(rootName trace:rootName rootServiceName trace:rootService),
       do: "complete-retained-trace-roots; exporter-completeness-unknown"

  defp discovery_coverage(scope, mode, query, version, key) do
    if scope == "intrinsic" and TempoIntrinsics.dynamic_key?(key),
      do: "stored-intrinsic-values; exporter-completeness-unknown",
      else: discovery_coverage(scope, mode, query, version)
  end

  defp discovery_coverage("intrinsic", _mode, _query, _version), do: "static-protocol-vocabulary; not-stored-values"

  defp discovery_coverage("none", :names, _query, 1), do: "stored-context-name-hints; not-key-presence"

  defp discovery_coverage("none", :names, _query, _version),
    do: "stored-context-name-hints-and-static-vocabulary; not-key-presence"

  defp discovery_coverage(_scope, :names, query, _version) when query not in [nil, "", "{}"],
    do: "stored-context-name-hints; not-matching-key-presence"

  defp discovery_coverage(_scope, _mode, _query, _version),
    do: "all-visible-stored-attributes; exporter-completeness-unknown"

  defp discovery_params(params, mode, version) do
    # Grafana's resource proxy retains its encoded `tag` query parameter.
    # As Tempo, use the path target and ignore that redundant parameter.
    allowed = if mode == :names, do: ~w(scope q start end limit), else: ~w(tag_name tag q start end limit)

    if Enum.all?(Map.keys(params), &(&1 in allowed)) do
      discovery_target(params, mode, version)
    else
      {:error, :unsupported_trace_discovery}
    end
  end

  # Pinned Tempo parses uint32 limits only for values. Names ignore the
  # parameter altogether; zero/empty/omission on values means no output cap.
  defp discovery_limit(_params, :names), do: {:ok, 0}

  defp discovery_limit(%{"limit" => value}, :values) when value not in [nil, ""] do
    if is_binary(value) and byte_size(value) <= 10 and Regex.match?(~r/\A[0-9]+\z/, value) do
      search_seconds(value, :limit)
    else
      search_parse_error(value, :limit)
    end
  end

  defp discovery_limit(_params, :values), do: {:ok, 0}

  defp discovery_window(params) do
    case {params["start"], params["end"]} do
      {nil, nil} ->
        {:ok, nil}

      {start, finish} ->
        with {:ok, start} when is_integer(start) and start > 0 <- seconds(start),
             {:ok, finish} when is_integer(finish) and finish >= start <- seconds(finish),
             true <- Regex.match?(~r/^[0-9]+$/, params["start"]) and Regex.match?(~r/^[0-9]+$/, params["end"]) do
          {:ok, {start * 1_000_000_000, finish * 1_000_000_000 + 999_999_999}}
        else
          _ -> {:error, :unsupported_parameters}
        end
    end
  end

  defp window_coverage(scope, key, nil) do
    if scope == "intrinsic" and not TempoIntrinsics.dynamic_key?(key),
      do: "static-protocol-vocabulary; window-independent",
      else: "all-retained"
  end

  defp window_coverage("intrinsic", key, _window)
       when key in ~w(rootName trace:rootName rootServiceName trace:rootService trace:duration),
       do: "retained-source-candidates-with-complete-trace-context; not-trace-time-filter"

  defp window_coverage("intrinsic", key, _window),
    do:
      if(TempoIntrinsics.dynamic_key?(key),
        do: "retention-visible-segment-envelope; not-span-time-filter",
        else: "static-protocol-vocabulary; window-independent"
      )

  defp window_coverage(_scope, _key, _window), do: "retention-visible-segment-envelope; not-span-time-filter"

  defp discovery_target(params, :names, _version) do
    scope = if params["scope"] in [nil, ""], do: "none", else: params["scope"]
    with :ok <- TempoDiscovery.target(scope, ""), do: {:ok, scope, ""}
  end

  defp discovery_target(%{"tag_name" => name}, :values, version) when is_binary(name) do
    if TempoIntrinsics.value_key?(name) do
      {:ok, "intrinsic", name}
    else
      stored_discovery_target(name, version)
    end
  end

  defp discovery_target(_params, _mode, _version), do: {:error, :unsupported_trace_discovery}

  defp stored_discovery_target(name, version) do
    case String.split(name, ".", parts: 2) do
      ["", key] when key != "" ->
        stored_discovery_key("none", key)

      [scope, key] when key != "" and scope in ["resource", "span", "instrumentation", "event", "link"] ->
        stored_discovery_key(scope, key)

      _ when version == 1 and name != "" ->
        with :ok <- TempoDiscovery.validate("none", name), do: {:ok, "none", name}

      _ ->
        {:error, :unsupported_trace_discovery}
    end
  end

  defp stored_discovery_key(scope, key) when byte_size(key) <= 2048 do
    with true <- String.valid?(key),
         {:ok, key} when key != "" <- discovery_key_parts(key),
         :ok <- TempoDiscovery.validate(scope, key) do
      {:ok, scope, key}
    else
      _ -> {:error, :unsupported_trace_discovery}
    end
  end

  defp stored_discovery_key(_scope, _key), do: {:error, :unsupported_trace_discovery}

  # Whole quoted keys retain the documented JSON-compatible escape contract.
  # A non-whole input falls through to the narrower mixed-portion grammar.
  defp discovery_key_parts(<<"\"", _rest::binary>> = key) do
    case Pulse.JSON.decode(key) do
      {:ok, decoded} when is_binary(decoded) -> {:ok, decoded}
      _ -> discovery_key_parts(key, [])
    end
  end

  defp discovery_key_parts(key), do: discovery_key_parts(key, [])

  # Normalize dot-separated quoted/ordinary portions only. Retain the existing
  # rejection of suffixes/adjacent quotes after a quoted portion, even though
  # Tempo's lexer accepts more general concatenation. Input bounds also bound
  # all temporary chunks; existing validation applies to the decoded key.
  defp discovery_key_parts(text, parts) do
    case :binary.split(text, "\"") do
      [ordinary] ->
        if ordinary_discovery_key?(ordinary),
          do: {:ok, IO.iodata_to_binary(Enum.reverse([ordinary | parts]))},
          else: :error

      [ordinary, quoted] ->
        with true <- ordinary_discovery_key?(ordinary),
             true <- ordinary == "" or String.ends_with?(ordinary, "."),
             {:ok, decoded, tail} <- discovery_quoted_key(quoted, []),
             true <- tail == "" or String.starts_with?(tail, ".") do
          discovery_key_parts(tail, [decoded, ordinary | parts])
        end
    end
  end

  defp ordinary_discovery_key?(key), do: not Regex.match?(~r/[\s{}()=~!<>&|^,"]/u, key)

  # Pinned Tempo parseQuotedAtrribute accepts only escaped quote/backslash,
  # not JSON control/Unicode escapes. Quoted dots remain literal key bytes;
  # retain the existing rejection of literal ASCII controls in quoted keys.
  defp discovery_quoted_key(<<"\"", rest::binary>>, parts), do: {:ok, IO.iodata_to_binary(Enum.reverse(parts)), rest}

  defp discovery_quoted_key(<<"\\", escaped, rest::binary>>, parts) when escaped in [?", ?\\],
    do: discovery_quoted_key(rest, [<<escaped>> | parts])

  defp discovery_quoted_key(<<"\\", _rest::binary>>, _parts), do: :error

  defp discovery_quoted_key(<<char::utf8, rest::binary>>, parts) when char >= 32,
    do: discovery_quoted_key(rest, [<<char::utf8>> | parts])

  defp discovery_quoted_key(_rest, _parts), do: :error

  def search(conn, params) do
    with {:ok, tenant} <- tenant(conn),
         :ok <- authorize(conn, tenant),
         true <- Enum.all?(Map.keys(params), &(&1 in ~w(q start end limit spss))),
         {:ok, {start, finish}} <- search_window(params),
         {:ok, limit} <- search_positive(params["limit"], :limit, 100, 1000),
         {:ok, spss} <- search_positive(params["spss"], :spss, 3, 100),
         {:ok, format} <- format(conn),
         {:ok, body} <-
           TempoSearch.query(
             tenant,
             params["q"],
             [trace_start: start * 1_000_000_000, trace_end: finish * 1_000_000_000, limit: limit, spss: spss],
             format
           ) do
      type = if format == "protobuf", do: "application/protobuf", else: "application/json"

      conn
      |> put_resp_content_type(type)
      |> put_resp_header("x-pulse-trace-coverage", "all-visible-stored-context; exporter-completeness-unknown")
      |> send_resp(200, body)
    else
      false -> failure(conn, :unsupported_parameters)
      {:error, reason} -> failure(conn, reason)
    end
  end

  defp search_window(params) do
    case {params["start"], params["end"]} do
      {nil, nil} ->
        {:ok, {0, 0}}

      {start, finish} when is_binary(start) and is_binary(finish) ->
        with {:ok, start_s} <- search_seconds(start, :start),
             {:ok, finish_s} <- search_seconds(finish, :end),
             true <- Regex.match?(~r/\A[0-9]+\z/, start) and Regex.match?(~r/\A[0-9]+\z/, finish),
             true <- (start_s == 0 and finish_s == 0) or (start_s > 0 and finish_s >= start_s) do
          {:ok, {start_s, finish_s}}
        else
          {:error, _reason} = error -> error
          _ -> {:error, :unsupported_parameters}
        end

      _ ->
        {:error, :unsupported_parameters}
    end
  end

  @doc "TraceQL metrics over a range (`Pulse.Traces.Metrics`). Requires Tempo search to be enabled."
  def metrics_query_range(conn, params), do: metrics(conn, params, false)

  @doc "Instant TraceQL metrics: one value per series over `[start, end]`."
  def metrics_query(conn, params), do: metrics(conn, params, true)

  defp metrics(conn, params, instant) do
    with {:ok, tenant} <- tenant(conn),
         :ok <- authorize(conn, tenant),
         :ok <- TempoSearch.available(),
         {:ok, query} <- metrics_text(params),
         {:ok, window} <- metrics_window(params, instant),
         {:ok, body} <- Metrics.query(tenant, query, window, instant) do
      conn
      |> put_resp_content_type("application/json")
      |> put_resp_header("x-pulse-trace-coverage", "all-visible-stored-spans; exporter-completeness-unknown")
      |> send_resp(200, body)
    else
      {:error, reason} -> failure(conn, reason)
    end
  end

  # Tempo reads `q`, falling back to the Prometheus-style `query`.
  defp metrics_text(%{"q" => q}) when is_binary(q) and q != "", do: {:ok, q}
  defp metrics_text(%{"query" => q}) when is_binary(q) and q != "", do: {:ok, q}
  defp metrics_text(_params), do: {:error, :unsupported_parameters}

  # As Tempo: `end` defaults to now, `start` to `since` (default 1h) before
  # `end`; times are Unix seconds (at most ten digits), nanoseconds, decimal
  # seconds or RFC3339; `step` is decimal seconds or a Go duration.
  defp metrics_window(params, instant) do
    now = System.system_time(:nanosecond)

    with {:ok, finish} <- tempo_time(params["end"], now, "end"),
         {:ok, since} <- tempo_duration(params["since"], 3_600_000_000_000, :since),
         {:ok, start} <- tempo_time(params["start"], min(finish, now) - since, "start"),
         {:ok, step} <- if(instant, do: {:ok, nil}, else: tempo_duration(params["step"], nil, :step)) do
      {:ok, {start, finish, step}}
    end
  end

  # Only metric timestamp parsing gets parameter context. Admitted timestamps
  # rejected by later window validation retain their existing policy errors.
  defp tempo_time(nil, default, _parameter), do: {:ok, default}

  defp tempo_time(value, _default, parameter) when is_binary(value) and byte_size(value) <= 64 do
    cond do
      Regex.match?(~r/\A[0-9]{1,10}\z/, value) ->
        {:ok, String.to_integer(value) * 1_000_000_000}

      Regex.match?(~r/\A[0-9]{11,19}\z/, value) ->
        {:ok, String.to_integer(value)}

      Regex.match?(~r/\A[0-9]+\.[0-9]+\z/, value) ->
        [whole, fraction] = String.split(value, ".")
        millis = fraction |> String.pad_trailing(3, "0") |> String.slice(0, 3) |> String.to_integer()
        {:ok, String.to_integer(whole) * 1_000_000_000 + millis * 1_000_000}

      true ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} -> {:ok, DateTime.to_unix(datetime, :nanosecond) + submicrosecond(value)}
          _ -> {:error, {:invalid_trace_metrics_timestamp, parameter}}
        end
    end
  end

  defp tempo_time(_value, _default, parameter), do: {:error, {:invalid_trace_metrics_timestamp, parameter}}

  # DateTime validates the existing ISO8601 grammar and applies the zone, but
  # keeps only microseconds. Restore the original fraction's final nanoseconds;
  # longer fractions still truncate, and numeric timestamps never use this path.
  defp submicrosecond(value) do
    case Regex.run(~r/[.,]([0-9]+)/, value, capture: :all_but_first) do
      [fraction] -> fraction |> String.pad_trailing(9, "0") |> String.slice(6, 3) |> String.to_integer()
      _ -> 0
    end
  end

  defp tempo_duration(nil, default, _parameter), do: {:ok, default}

  defp tempo_duration(value, _default, parameter) do
    case parse_tempo_duration(value) do
      {:ok, ns} when ns > 0 ->
        {:ok, ns}

      {:ok, ns} when ns < 0 and parameter == :step ->
        {:error, {:negative_trace_metrics_step, value}}

      {:error, _reason} when parameter == :since ->
        {:error, :invalid_trace_metrics_since}

      _ ->
        {:error, :unsupported_parameters}
    end
  end

  # The existing Go-duration parser is unsigned. Reuse its grammar after a
  # single minus, without admitting signed PromQL-only units such as days.
  defp parse_tempo_duration("-" <> unsigned = value) do
    with {:error, _} <- Pulse.PromQL.Time.parse_seconds(value),
         {:ok, ns} <- SearchExpression.go_duration(unsigned) do
      {:ok, -ns}
    end
  end

  # Keep the existing duration parsers and their precedence; parameter-specific
  # diagnostics are selected only after parsing.
  defp parse_tempo_duration(value) when is_binary(value) do
    with {:error, _} <- Pulse.PromQL.Time.parse_seconds(value),
         {:error, _} <- SearchExpression.go_duration(value) do
      Parser.parse_duration(value)
    end
  end

  defp parse_tempo_duration(_value), do: {:error, :unsupported_parameters}

  defp search_positive(nil, _parameter, default, _max), do: {:ok, default}

  defp search_positive(value, parameter, _default, max) do
    case search_seconds(value, parameter) do
      {:ok, n} when n >= 1 and n <= max -> {:ok, n}
      {:ok, 0} when parameter == :limit -> {:error, {:invalid_trace_search_limit, :zero}}
      {:ok, _n} -> {:error, :unsupported_parameters}
      {:error, _reason} = error -> error
    end
  end

  defp search_seconds(value, parameter) do
    case seconds(value) do
      {:ok, _n} = result -> result
      _ -> search_parse_error(value, parameter)
    end
  end

  # Preserve seconds/1 admission and its ten-byte bound. Only classify a
  # rejected bounded value; operator caps and larger inputs stay generic.
  defp search_parse_error(value, parameter) when is_binary(value) and byte_size(value) <= 10 do
    reason = if Regex.match?(~r/\A[0-9]+\z/, value), do: :range, else: :syntax
    {:error, {:invalid_trace_search_parameter, parameter, reason, value}}
  end

  defp search_parse_error(_value, _parameter), do: {:error, :unsupported_parameters}

  def trace(conn, params), do: lookup(conn, params, false)
  def trace_v2(conn, params), do: lookup(conn, params, true)

  defp lookup(conn, params, v2) do
    with {:ok, tenant} <- tenant(conn),
         :ok <- authorize(conn, tenant),
         {:ok, filter} <- parameters(params, v2),
         {:ok, trace_id} <- trace_id(params["trace_id"]),
         {:ok, format} <- format(conn),
         export_format = if(v2, do: format <> "_v2", else: format),
         {:ok, body} <- Tempo.lookup(tenant, trace_id, export_format, filter) do
      type = if format == "protobuf", do: "application/protobuf", else: "application/json"
      coverage = if filter, do: "explicit-filter-subset-of-all-visible-stored-spans", else: "all-visible-stored-spans"

      conn
      |> put_resp_content_type(type)
      |> put_resp_header("x-pulse-trace-coverage", coverage <> "; exporter-completeness-unknown")
      |> send_resp(200, body)
    else
      {:error, reason} -> failure(conn, reason)
    end
  end

  defp tenant(conn) do
    case get_req_header(conn, "x-scope-orgid") do
      [] -> {:ok, "default"}
      [value] when value != "" -> {:ok, value}
      _ -> {:error, :invalid_tenant_header}
    end
  end

  defp authorize(conn, tenant) do
    case Auth.verify(conn, tenant, :read) do
      :ok -> :ok
      {:error, reason} when reason in [:forbidden, :auth_unavailable] -> {:error, reason}
      {:error, _} -> {:error, :unauthorized}
    end
  end

  defp trace_id(value) when is_binary(value) and byte_size(value) in 1..32 do
    Traces.id(String.pad_leading(value, 32, "0"), 32)
    |> case do
      {:ok, id} -> {:ok, id}
      _ -> {:error, :invalid_trace_id}
    end
  end

  defp trace_id(_value), do: {:error, :invalid_trace_id}

  defp parameters(params, v2) do
    allowed = ~w(trace_id start end mode allowPartialTrace)
    allowed = if v2, do: allowed ++ ~w(q keep_hierarchy match_depth ancestor_depth), else: allowed

    with true <- Enum.all?(Map.keys(params), &(&1 in allowed)),
         true <- Map.get(params, "mode", "all") == "all",
         true <- Map.get(params, "allowPartialTrace", "false") == "false",
         :ok <- time_hints(params) do
      if v2, do: TempoFilter.parse(params), else: {:ok, nil}
    else
      _ -> {:error, :unsupported_parameters}
    end
  end

  defp time_hints(params) do
    with {:ok, start} <- seconds(params["start"]),
         {:ok, finish} <- seconds(params["end"]),
         true <- is_nil(start) or is_nil(finish) or start <= finish do
      :ok
    else
      _ -> {:error, :unsupported_parameters}
    end
  end

  defp seconds(nil), do: {:ok, nil}

  defp seconds(value) when is_binary(value) and byte_size(value) <= 10 do
    case Integer.parse(value) do
      {number, ""} when number in 0..4_294_967_295 -> {:ok, number}
      _ -> {:error, :unsupported_parameters}
    end
  end

  defp seconds(_value), do: {:error, :unsupported_parameters}

  defp format(conn) do
    case get_req_header(conn, "accept") do
      [""] -> {:ok, "json"}
      ["application/protobuf"] -> {:ok, "protobuf"}
      values -> json_format(values)
    end
  end

  defp json_format(values) do
    types =
      Enum.flat_map(values, &String.split(&1, ",")) |> Enum.map(&(&1 |> String.split(";") |> hd() |> String.trim()))

    if types == [] or Enum.any?(types, &(&1 in ["application/json", "*/*"])),
      do: {:ok, "json"},
      else: {:error, :unsupported_accept}
  end

  defp failure(conn, :unauthorized), do: error(conn, 401, "unauthorized")
  defp failure(conn, :forbidden), do: error(conn, 403, "forbidden")
  defp failure(conn, :auth_unavailable), do: error(conn, 503, "auth_unavailable")

  defp failure(conn, :invalid_tenant_header),
    do: error(conn, 400, "exactly one nonempty tenant header is required when supplied")

  defp failure(conn, :tempo_search_disabled),
    do:
      error(
        conn,
        501,
        "experimental Tempo search disabled; requires explicit operator opt-in and retained-context capacity validation"
      )

  defp failure(conn, :not_found), do: send_resp(conn, 404, "")

  defp failure(conn, {:invalid_trace_search_limit, :zero}),
    do: error(conn, 400, "invalid limit: must be a positive number")

  defp failure(conn, {:invalid_trace_search_parameter, parameter, reason, value}) do
    detail = if reason == :range, do: "value out of range", else: "invalid syntax"
    error(conn, 400, "invalid #{parameter}: strconv.ParseUint: parsing #{Pulse.GoUnicode.quote(value)}: #{detail}")
  end

  defp failure(conn, {:invalid_trace_metrics_timestamp, parameter}),
    do: error(conn, 400, "could not parse '#{parameter}' parameter")

  defp failure(conn, :invalid_trace_metrics_since), do: error(conn, 400, "could not parse 'since' parameter:")

  defp failure(conn, {:negative_trace_metrics_step, value}),
    do: error(conn, 400, "cannot parse #{inspect(value)}: step must be positive")

  defp failure(conn, {:trace_metrics_step_too_small, step, minimum}) do
    error(
      conn,
      400,
      "step of #{TempoDuration.format(step)} is too small, minimum step for given range is #{TempoDuration.format(minimum)}"
    )
  end

  defp failure(conn, reason)
       when reason in [
              :invalid_trace_id,
              :unsupported_parameters,
              :unsupported_trace_selector,
              :unsupported_trace_discovery,
              :unexpanded_trace_variable,
              :query_expression_limit
            ], do: error(conn, 400, "invalid or unsupported trace lookup parameters")

  defp failure(conn, {:invalid_tenant, _}), do: error(conn, 400, "invalid tenant")
  defp failure(conn, {:decode_failed, _}), do: error(conn, 500, "stored trace data is invalid")
  defp failure(conn, :query_execution_failed), do: error(conn, 500, "trace query execution failed")

  defp failure(conn, :unsupported_accept),
    do: error(conn, 406, "supported trace response formats: application/json, application/protobuf")

  defp failure(conn, :query_overloaded),
    do: conn |> put_resp_header("retry-after", "1") |> error(429, "query capacity busy")

  defp failure(conn, :query_timeout), do: error(conn, 504, "trace query timed out")

  defp failure(conn, reason) when reason in @conflicts, do: error(conn, 409, Atom.to_string(reason))

  defp failure(conn, reason)
       when reason in [
              :query_scan_limit,
              :query_sample_limit,
              :query_resource_limit,
              :trace_group_limit,
              :trace_duration_limit,
              :trace_discovery_work_limit
            ], do: error(conn, 422, "complete trace exceeds query safety budgets")

  defp failure(conn, :unsupported_trace_tag_type),
    do:
      error(
        conn,
        422,
        "trace tag values require original string, int64 or boolean types; floats/complex values are unsupported, not coerced or omitted"
      )

  defp failure(conn, :invalid_trace_export), do: error(conn, 500, "stored trace cannot be exported faithfully")
  defp failure(conn, _reason), do: error(conn, 503, "trace storage unavailable")
  defp error(conn, status, message), do: conn |> put_resp_content_type("text/plain") |> send_resp(status, message)
end
