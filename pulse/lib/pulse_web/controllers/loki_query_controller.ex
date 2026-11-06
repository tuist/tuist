defmodule PulseWeb.LokiQueryController do
  @moduledoc """
  Loki-compatible query endpoints backed by `Pulse.LogQL.Evaluator`.

  Routes served here are the read-side complement of
  `PulseWeb.LokiController`'s push endpoint. They accept the same
  `X-Scope-OrgID` tenant header and pass every request through
  `Pulse.Auth.verify/3` so a shared-secret deployment applies uniformly
  across ingest and query.

  Finite reads accept `X-Loki-Query-Limits: {"maxQueryLength":"1m"}` as
  an additional request-local time-window ceiling. Queries also support
  `maxQueryInterval`, `maxEntriesLimitPerQuery`, `requiredLabels` and
  `minimumLabelsNumber`. `maxQueryTime` tightens worker deadlines for finite
  reads; invalid/ambiguous or unsupported policies reject rather than run unlimited.
  Existing server admission and resource budgets always remain authoritative.

  Endpoints:

    * `GET|POST /loki/api/v1/query_range` — log selection over `[start,
      end)` returning `streams`; metric evaluation over `[start, end]` at
      `step` returning `matrix`. Only external raw-log range bounds are
      normalized; shared evaluator/storage bounds remain inclusive.
    * `GET|POST /loki/api/v1/query` — instant query at `time`. Returns
      `streams` for log queries and `vector` for metric queries.
    * `GET /loki/api/v1/labels` — list of every label name seen across
      the tenant's segments within `[start, end]`.
    * `GET /loki/api/v1/label/:name/values` — list of every value seen
      for one label within `[start, end]`.
  """

  use PulseWeb, :controller

  alias Pulse.Auth
  alias Pulse.LogQL.AST
  alias Pulse.LogQL.Entry
  alias Pulse.LogQL.Envelope
  alias Pulse.LogQL.Evaluator
  alias Pulse.LogQL.Parser
  alias Pulse.LogQL.Quantity
  alias Pulse.LogQL.QueryValidation
  alias Pulse.LogQL.StreamMatchers
  alias Pulse.Loki.Detected
  alias Pulse.Loki.Discovery
  alias Pulse.Loki.HTTPParams
  alias Pulse.Loki.LabelVolume
  alias Pulse.Loki.Patterns
  alias Pulse.Loki.Tail
  alias Pulse.QueryLimit
  alias Pulse.QueryRunner
  alias Pulse.Storage

  @default_tenant "default"
  # ---------------------------------------------------------------------------
  # query_range
  # ---------------------------------------------------------------------------

  def query_range(conn, params), do: run_query(conn, params, :range)

  # ---------------------------------------------------------------------------
  # query (instant)
  # ---------------------------------------------------------------------------

  def query(conn, params), do: run_query(conn, params, :instant)

  defp run_query(conn, params, mode) do
    tenant = tenant_from(conn)

    with :ok <- Auth.verify(conn, tenant, :read),
         {:ok, query_str} <- require_query(params),
         {:ok, ast} <- parse_query(query_str),
         {:ok, opts} <- HTTPParams.query(params, mode),
         {:ok, limits} <- request_query_limits(conn),
         :ok <- validate_query_length(limits, query_window_start(ast, opts), opts.end_ts_ns),
         :ok <- query_expression_limits(ast, opts, limits),
         :ok <- query_matcher_limits(ast, limits) do
      dispatch_eval(conn, ast, tenant, query_timeout(opts, limits), mode)
    else
      err -> render_error(conn, err)
    end
  end

  # Admission above uses the original external bounds. Normalize only raw-log
  # range dispatch, before selection/top-k, to the shared inclusive reader.
  # Equal bounds are empty, including int64 minimum: never subtract from that
  # endpoint or consult storage, but keep ordinary static stage validation.
  defp dispatch_eval(conn, %AST.LogQuery{} = ast, tenant, opts, :range) when opts.start_ts_ns == opts.end_ts_ns do
    result =
      Pulse.SelfMetrics.track(:query, :logql_log, fn ->
        QueryRunner.run(
          tenant,
          :logql,
          fn deadline ->
            Process.put(:query_deadline_ms, deadline)
            QueryValidation.validate(ast)
          end,
          opts
        )
      end)

    case result do
      :ok -> json(conn, Envelope.streams([], response_encoding_flags(conn)))
      {:error, reason} -> render_query_error(conn, reason)
    end
  end

  defp dispatch_eval(conn, %AST.LogQuery{} = ast, tenant, opts, :range),
    do: dispatch_eval(conn, ast, tenant, %{opts | end_ts_ns: opts.end_ts_ns - 1})

  defp dispatch_eval(conn, ast, tenant, opts, _mode), do: dispatch_eval(conn, ast, tenant, opts)

  defp dispatch_eval(conn, %AST.LogQuery{} = ast, tenant, opts) do
    flags = response_encoding_flags(conn)
    opts = Map.put(opts, :categorize_labels, "categorize-labels" in flags)

    case Evaluator.evaluate_log(ast, tenant, opts) do
      {:ok, streams} -> json(conn, Envelope.streams(streams, flags))
      {:error, reason} -> render_query_error(conn, reason)
    end
  end

  defp dispatch_eval(conn, ast, tenant, opts) do
    flags = response_encoding_flags(conn)

    case Evaluator.evaluate_metric(ast, tenant, opts) do
      {:ok, {:matrix, series}} -> json(conn, Envelope.matrix(series, flags))
      {:ok, {:vector, series}} -> json(conn, Envelope.vector(series, flags))
      {:ok, {:scalar, series}} -> json(conn, Envelope.scalar(series, flags))
      {:error, reason} -> render_query_error(conn, reason)
    end
  end

  # Flags are opaque, comma-separated tokens. Like Loki, echo unknown tokens
  # without assigning them behavior. Only the exact known token opts into
  # category tracking; no header leaves the existing representation untouched.
  defp response_encoding_flags(conn) do
    conn
    |> get_req_header("x-loki-response-encoding-flags")
    |> Enum.flat_map(fn
      "" -> []
      value -> String.split(value, ",")
    end)
    |> Enum.uniq()
  end

  # ---------------------------------------------------------------------------
  # labels / label values / series — complete stream-label dictionaries
  # from `Pulse.Loki.Discovery`. Like Loki, an omitted range is the last
  # hour, and `query` (labels/values) or `match[]` (series) selects
  # streams with log-query matcher semantics.
  # ---------------------------------------------------------------------------

  def labels(conn, params), do: discover(conn, params, :names, "", "query")

  def label_values(conn, %{"name" => name} = params), do: discover(conn, params, :values, name, "query")

  def series(conn, params) do
    matches =
      [conn.query_string, Map.get(conn.assigns, :prometheus_discovery_form, "")]
      |> Enum.flat_map(&Enum.to_list(URI.query_decoder(&1)))
      |> Enum.filter(fn {key, _} -> key in ["match", "match[]"] end)
      |> Enum.map(&elem(&1, 1))
      |> Enum.uniq()
      |> Enum.sort()

    matches =
      case matches do
        [one] -> if String.replace(one, " ", "") == "{}", do: [], else: matches
        _ -> matches
      end

    discover(conn, Map.put(params, "match", matches), :series, "", "match")
  end

  defp discover(conn, params, mode, key, selector_param) do
    tenant = tenant_from(conn)

    # Loki's Form.Get takes the first value, with the POST body before the URL.
    # The discovery gate has already bounded both raw inputs; keep selector
    # unions and path parameters separate from these four scalar parameters.
    scalars =
      for raw <- [Map.get(conn.assigns, :prometheus_discovery_form, ""), conn.query_string],
          {name, value} <- URI.query_decoder(raw),
          name in ["query", "start", "end", "since"],
          reduce: %{} do
        acc -> Map.put_new(acc, name, value)
      end

    # Go keeps bracketed names literal; Plug expands them into lists/maps.
    # Only exact raw scalar names may supply these values.
    params = params |> Map.drop(["query", "start", "end", "since"]) |> Map.merge(scalars)

    with :ok <- Auth.verify(conn, tenant, :read),
         {:ok, selectors} <- discovery_selectors(params, selector_param),
         {:ok, times} <- discovery_times(params),
         {:ok, times} <- query_window_limits(conn, times),
         {:ok, json} <- Discovery.query(tenant, mode, key, selectors, times) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, [~s({"status":"success","data":), json, "}"])
    else
      err -> render_error(conn, err)
    end
  end

  # `match[]` repeats; `query` and Loki's legacy singular `match` do not.
  defp discovery_selectors(params, name) do
    values =
      case params[name] do
        nil -> []
        "" -> []
        value when is_binary(value) -> [value]
        values when is_list(values) -> values
        _ -> :invalid
      end

    if values == :invalid or not Enum.all?(values, &(is_binary(&1) and byte_size(&1) <= 8192)),
      do: {:error, {:invalid_query_parameter, name}},
      else: parse_selectors(values, name)
  end

  defp parse_selectors(values, name) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case Parser.parse(value) do
        {:ok, %AST.LogQuery{selector: selector, stages: []}} -> {:cont, {:ok, [selector | acc]}}
        {:ok, %AST.LogQuery{}} -> {:halt, {:error, :label_matchers_only}}
        _ -> {:halt, {:error, {:invalid_query_parameter, name}}}
      end
    end)
    |> case do
      {:ok, selectors} -> {:ok, Enum.reverse(selectors)}
      error -> error
    end
  end

  defp discovery_times(params) do
    with {:ok, times} <- HTTPParams.bounds(params),
         :ok <- HTTPParams.ordered(times) do
      {:ok, times}
    end
  end

  # ---------------------------------------------------------------------------
  # index/stats, index/volume, index/volume_range, status/buildinfo
  # ---------------------------------------------------------------------------

  @doc """
  Approximate query size, which Grafana shows before running a query.
  Whole matching segments are counted from manifest metadata, so this is
  an upper bound that never reads logs. Pulse does not index streams, so
  `streams` is not estimated.
  """
  def index_stats(conn, params) do
    tenant = tenant_from(conn)

    with :ok <- Auth.verify(conn, tenant, :read),
         {:ok, selectors} <- discovery_selectors(params, "query"),
         {:ok, opts} <- HTTPParams.query(params, :range),
         times = %{start_ns: opts.start_ts_ns, end_ns: opts.end_ts_ns},
         {:ok, times} <- query_window_limits(conn, times),
         {:ok, stats} <- index_stats(tenant, selectors, times) do
      json(conn, %{"streams" => 0, "chunks" => stats.segments, "entries" => stats.entries, "bytes" => stats.bytes})
    else
      err -> render_error(conn, err)
    end
  end

  defp index_stats(tenant, selectors, times) do
    service =
      case selectors do
        [selector] -> selector.matchers |> StreamMatchers.split() |> elem(0)
        _ -> nil
      end

    QueryRunner.run(
      tenant,
      :discovery,
      fn deadline ->
        opts = [start_ts: times.start_ns, end_ts: times.end_ns] ++ QueryRunner.storage_opts(deadline)
        opts = if service, do: Keyword.put(opts, :service, service), else: opts
        Storage.log_index_stats(tenant, opts)
      end,
      times
    )
  end

  @doc """
  Log volume in bytes per stream group or label name, as Loki's volume API.
  Series groups use `targetLabels` or the selector's label names; label
  aggregation counts all stream names unless `targetLabels` is supplied.
  """
  def volume(conn, params), do: volume(conn, params, :instant)

  def volume_range(conn, params), do: volume(conn, params, :range)

  defp volume(conn, params, mode) do
    with :ok <- Auth.verify(conn, tenant_from(conn), :read),
         {:ok, _opts} <- HTTPParams.query(params, mode),
         :ok <- volume_aggregation(params["aggregateBy"]) do
      if params["aggregateBy"] == "labels",
        do: label_volume(conn, params, mode),
        else: series_volume(conn, params, mode)
    else
      err -> render_error(conn, err)
    end
  end

  defp label_volume(conn, params, mode) do
    with {:ok, query, selector} <- volume_selector(params),
         {:ok, ast} <- Parser.parse(query),
         {:ok, times} <- discovery_times(params),
         {:ok, times} <- query_window_limits(conn, times),
         {:ok, limit} <- volume_limit(params["limit"]),
         {:ok, targets} <- label_volume_targets(params["targetLabels"], selector),
         {:ok, step} <- label_volume_step(mode, params["step"], times),
         {:ok, result} <- LabelVolume.query(tenant_from(conn), ast, times, targets, limit, step) do
      case result do
        {:vector, series} -> json(conn, Envelope.vector(series))
        {:matrix, series} -> json(conn, Envelope.matrix(series))
      end
    else
      {:error, {:invalid_regex, _, _, _} = reason} -> render_query_error(conn, reason)
      err -> render_error(conn, err)
    end
  end

  defp label_volume_targets(value, _selector) when value in [nil, ""], do: {:ok, nil}
  defp label_volume_targets(value, selector), do: volume_labels(value, selector)

  defp label_volume_step(:instant, _value, _times), do: {:ok, nil}

  defp label_volume_step(:range, value, times) do
    with {:ok, step} <- HTTPParams.step(value, times.start_ns, times.end_ns),
         true <- step >= 1_000_000,
         last = max(times.start_ns, times.end_ns - 1),
         true <-
           Integer.floor_div(last, step) - Integer.floor_div(times.start_ns, step) <
             Pulse.QueryLimits.max_evaluation_steps() do
      {:ok, step}
    else
      _ -> {:error, {:invalid_query_parameter, "step"}}
    end
  end

  defp series_volume(conn, params, mode) do
    with {:ok, query, selector} <- volume_selector(params),
         {:ok, times} <- discovery_times(params),
         {:ok, times} <- query_window_limits(conn, times),
         {:ok, limit} <- volume_limit(params["limit"]),
         :ok <- volume_aggregation(params["aggregateBy"]),
         {:ok, labels} <- volume_labels(params["targetLabels"], selector),
         {:ok, step_ns} <- label_volume_step(mode, params["step"], times) do
      grouping = Enum.join(labels, ",")
      range_ms = max(1, div(times.end_ns - times.start_ns, 1_000_000))

      {expression, overrides} =
        case mode do
          :instant ->
            {"topk(#{limit}, sum by (#{grouping}) (bytes_over_time(#{query}[#{range_ms}ms])))",
             %{"time" => Integer.to_string(times.end_ns)}}

          :range ->
            step = "#{div(step_ns, 1_000_000)}ms"

            {"sum by (#{grouping}) (bytes_over_time(#{query}[#{step}]))",
             %{"start" => Integer.to_string(times.start_ns), "end" => Integer.to_string(times.end_ns), "step" => step}}
        end

      run_query(conn, Map.merge(%{"query" => expression}, overrides), mode)
    else
      err -> render_error(conn, err)
    end
  end

  defp volume_selector(%{"query" => query}) when is_binary(query) and byte_size(query) in 1..8192 do
    case Parser.parse(query) do
      {:ok, %AST.LogQuery{selector: selector}} -> {:ok, query, selector}
      _ -> {:error, {:invalid_query_parameter, "query"}}
    end
  end

  defp volume_selector(_params), do: {:error, {:missing_param, "query"}}

  defp volume_limit(value) when value in [nil, ""], do: {:ok, 100}

  defp volume_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {limit, ""} when limit in 1..5000 -> {:ok, limit}
      _ -> {:error, {:invalid_query_parameter, "limit"}}
    end
  end

  defp volume_limit(_value), do: {:error, {:invalid_query_parameter, "limit"}}

  defp volume_aggregation(value) when value in [nil, "", "series", "labels"], do: :ok
  defp volume_aggregation(_value), do: {:error, {:http_parameter_error, "aggregateBy", "invalid aggregation option"}}

  defp volume_labels(value, selector) when value in [nil, ""],
    do: selector.matchers |> Enum.map(& &1.name) |> Enum.uniq() |> valid_labels()

  defp volume_labels(value, _selector) when is_binary(value),
    do: value |> String.split(",", trim: true) |> Enum.map(&String.trim/1) |> Enum.uniq() |> valid_labels()

  defp volume_labels(_value, _selector), do: {:error, {:invalid_query_parameter, "targetLabels"}}

  defp valid_labels(labels) do
    if labels != [] and length(labels) <= 32 and Enum.all?(labels, &Regex.match?(~r/\A[a-zA-Z_][a-zA-Z0-9_]*\z/, &1)),
      do: {:ok, labels},
      else: {:error, {:invalid_query_parameter, "targetLabels"}}
  end

  # ---------------------------------------------------------------------------
  # detected_labels / detected_fields / detected_field values (`Pulse.Loki.Detected`)
  # ---------------------------------------------------------------------------

  @doc "Stream labels and their cardinality, for Grafana's label suggestions."
  def detected_labels(conn, params) do
    tenant = tenant_from(conn)

    with :ok <- Auth.verify(conn, tenant, :read),
         {:ok, selectors} <- discovery_selectors(params, "query"),
         {:ok, window} <- detected_window(params),
         {:ok, window} <- query_window_limits(conn, window),
         {:ok, labels} <- Detected.labels(tenant, selectors, window) do
      json(conn, %{"detectedLabels" => Enum.map(labels, &%{"label" => &1.label, "cardinality" => &1.cardinality})})
    else
      err -> render_error(conn, err)
    end
  end

  @doc "Fields detected in the newest `line_limit` lines a log query selects."
  def detected_fields(conn, params) do
    with {:ok, tenant, ast, window, line_limit, limit} <- detected_request(conn, params),
         {:ok, fields} <- Detected.fields(tenant, ast, window, line_limit, limit) do
      json(
        conn,
        if(fields == [], do: %{}, else: %{"fields" => Enum.map(fields, &detected_field_json/1), "limit" => limit})
      )
    else
      err -> render_error(conn, err)
    end
  end

  @doc "Values of one detected field in the newest `line_limit` lines a log query selects."
  def detected_field_values(conn, %{"name" => name} = params) do
    with {:ok, tenant, ast, window, line_limit, limit} <- detected_request(conn, params),
         {:ok, values} <- Detected.values(tenant, ast, name, window, line_limit, limit) do
      json(conn, if(values == [], do: %{}, else: %{"values" => values, "limit" => limit}))
    else
      err -> render_error(conn, err)
    end
  end

  defp detected_field_json(field) do
    base = %{
      "label" => field.label,
      "type" => field.type,
      "cardinality" => field.cardinality,
      "parsers" => field.parsers
    }

    if field.json_path, do: Map.put(base, "jsonPath", field.json_path), else: base
  end

  defp detected_request(conn, params) do
    tenant = tenant_from(conn)
    limit = if params["limit"] in [nil, ""], do: params["field_limit"], else: params["limit"]

    with :ok <- Auth.verify(conn, tenant, :read),
         {:ok, query_str} <- require_query(params),
         {:ok, ast} <- tail_query(query_str),
         :ok <- tail_validate(ast),
         {:ok, window} <- detected_window(params),
         {:ok, limits} <- request_query_limits(conn),
         :ok <- validate_query_length(limits, window.start_ns, window.end_ns),
         {:ok, line_limit} <- detected_limit(params["line_limit"], 100, "line_limit"),
         {:ok, limit} <- detected_limit(limit, 1000, "limit"),
         {:ok, step} <- HTTPParams.step(params["step"], window.start_ns, window.end_ns),
         :ok <- if(step >= 1_000_000, do: :ok, else: {:error, {:invalid_query_parameter, "step"}}),
         :ok <- query_expression_limits(ast, %{limit: line_limit}, limits),
         :ok <- query_matcher_limits(ast, limits) do
      {:ok, tenant, ast, query_timeout(window, limits), line_limit, limit}
    end
  end

  defp detected_limit(value, default, name) do
    case HTTPParams.uint32(value, name, default) do
      {:ok, n} when n <= 5000 -> {:ok, n}
      _ -> {:error, {:invalid_query_parameter, name}}
    end
  end

  defp detected_window(params), do: discovery_times(params)

  # ---------------------------------------------------------------------------
  # patterns (`Pulse.Loki.Patterns`)
  # ---------------------------------------------------------------------------

  @doc """
  Log patterns with their line counts per `step`, mined from the lines a log
  query selects. `step` defaults to Loki's range step (the window over 250,
  at least one second); at most 11,000 steps per pattern.
  """
  def patterns(conn, params) do
    tenant = tenant_from(conn)

    with :ok <- Auth.verify(conn, tenant, :read),
         {:ok, query_str} <- require_query(params),
         {:ok, ast} <- tail_query(query_str),
         {:ok, window} <- detected_window(params),
         {:ok, limits} <- request_query_limits(conn),
         :ok <- validate_query_length(limits, window.start_ns, window.end_ns),
         :ok <- query_matcher_limits(ast, limits),
         {:ok, step} <- HTTPParams.step(params["step"], window.start_ns, window.end_ns),
         {:ok, patterns} <- Patterns.query(tenant, ast, window |> Map.put(:step_ns, step) |> query_timeout(limits)) do
      data =
        Enum.map(patterns, fn {pattern, samples} ->
          %{"pattern" => pattern, "samples" => Enum.map(samples, fn {ts, n} -> [div(ts, 1_000_000_000), n] end)}
        end)

      json(conn, %{"status" => "success", "data" => data})
    else
      err -> render_error(conn, err)
    end
  end

  # ---------------------------------------------------------------------------
  # tail — live logs over WebSocket (`PulseWeb.LokiTail`)
  # ---------------------------------------------------------------------------

  @doc """
  Loki's live tail. Like Loki, the socket first receives the newest `limit`
  entries since `start` (default: one hour ago), oldest first, then every
  newly acknowledged matching entry. `delay_for` (at most 5 seconds) is
  accepted for compatibility; entries are sent as soon as they are appended.
  """
  def tail(conn, params) do
    tenant = tenant_from(conn)
    config = Pulse.Runtime.get_env(:pulse, Tail, [])

    with :ok <- Auth.verify(conn, tenant, :read),
         :ok <- tail_query_limits(conn),
         :ok <- websocket_upgrade(conn),
         {:ok, query_str} <- require_query(params),
         {:ok, %AST.LogQuery{} = ast} <- tail_query(query_str),
         :ok <- tail_validate(ast),
         {:ok, limit} <- tail_limit(params["limit"], Keyword.get(config, :max_limit, 5000)),
         :ok <- tail_delay(params["delay_for"]),
         {:ok, times} <- discovery_times(params),
         {:ok, follower} <- Tail.join(tenant, Keyword.get(config, :max_per_tenant, 10)),
         {:ok, history} <- tail_history(ast, tenant, times.start_ns, limit) do
      state = %{
        tenant: tenant,
        follower: follower,
        compiled: Tail.compile(ast),
        limit: limit,
        max_backlog: Keyword.get(config, :max_backlog, 64),
        history: history
      }

      conn
      |> WebSockAdapter.upgrade(PulseWeb.LokiTail, state, timeout: :infinity)
      |> halt()
    else
      {:error, :too_many_tails} ->
        error_json(conn, :too_many_requests, "too_many_tails", "The tenant has reached its live tail limit.")

      {:error, :tail_unavailable} ->
        error_json(
          conn,
          :service_unavailable,
          "tail_unavailable",
          "Live tail is temporarily unavailable. Reconnect and query history."
        )

      {:error, {:invalid_query_limits, _}} = err ->
        render_error(conn, err)

      err ->
        :ok = Tail.leave(tenant)
        render_error(conn, err)
    end
  end

  defp websocket_upgrade(conn) do
    upgrade = conn |> get_req_header("upgrade") |> Enum.map(&String.downcase/1)
    if "websocket" in upgrade, do: :ok, else: {:error, {:invalid_query_parameter, "upgrade"}}
  end

  # A live tail has no finite end; do not claim to enforce a duration policy.
  defp tail_query_limits(conn) do
    if get_req_header(conn, "x-loki-query-limits") == [],
      do: :ok,
      else: {:error, {:invalid_query_limits, "not supported for live tail"}}
  end

  defp tail_query(query_str) do
    case parse_query(query_str) do
      {:ok, %AST.LogQuery{}} = ok -> ok
      {:ok, _metric} -> {:error, {:invalid_query_parameter, "query"}}
      error -> error
    end
  end

  defp tail_validate(ast) do
    case QueryValidation.validate(ast) do
      :ok -> :ok
      {:error, reason} -> {:error, {:parse_error, reason}}
    end
  end

  defp tail_limit(value, max) do
    case HTTPParams.uint32(value, "limit", 100) do
      {:ok, n} when n <= max -> {:ok, n}
      _ -> {:error, {:invalid_query_parameter, "limit"}}
    end
  end

  defp tail_delay(value) do
    case HTTPParams.uint32(value, "delay_for", 0, 0) do
      {:ok, n} when n <= 5 -> :ok
      _ -> {:error, {:invalid_query_parameter, "delay_for"}}
    end
  end

  # The connection already receives live entries, so the history window
  # ends now and the two overlap rather than leave a gap.
  defp tail_history(ast, tenant, start, limit) do
    now = System.system_time(:nanosecond)
    opts = %{start_ts_ns: start || now - 3_600_000_000_000, end_ts_ns: now, limit: limit, direction: :backward}

    case Evaluator.evaluate_log(ast, tenant, opts) do
      {:ok, streams} ->
        entries =
          for {labels, values} <- streams, {ts, line} <- values do
            %Entry{labels: labels, timestamp_ns: ts, line: line}
          end

        {:ok, Enum.sort_by(entries, & &1.timestamp_ns)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Loki build information; Grafana uses it to detect API features."
  def buildinfo(conn, _params) do
    json(conn, %{
      "version" => "3.5.0",
      "revision" => "pulse-" <> pulse_version(),
      "branch" => "",
      "buildUser" => "",
      "buildDate" => "",
      "goVersion" => ""
    })
  end

  defp pulse_version, do: :pulse |> Application.spec(:vsn) |> to_string()

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp require_query(%{"query" => q}) when is_binary(q) and byte_size(q) > 0, do: {:ok, q}
  defp require_query(_), do: {:error, {:missing_param, "query"}}

  defp parse_query(str) do
    case Parser.parse(str) do
      {:ok, ast} -> {:ok, ast}
      {:error, reason} -> {:error, {:parse_error, reason}}
    end
  end

  # Instant metrics have a zero evaluation window. Their range selectors are
  # not maxQueryLength (Loki calls that separate policy maxQueryInterval).
  # An instant log query without `start` has no finite lower bound here.
  defp query_window_start(%AST.LogQuery{}, opts), do: Map.get(opts, :start_ts_ns)
  defp query_window_start(_ast, opts), do: Map.get(opts, :start_ts_ns, opts.end_ts_ns)

  defp query_window_limits(conn, times) do
    with {:ok, limits} <- request_query_limits(conn),
         :ok <- validate_query_length(limits, times.start_ns, times.end_ns) do
      {:ok, query_timeout(times, limits)}
    end
  end

  # Model durations have millisecond precision. Zero leaves the server timeout
  # intact; QueryRunner caps every positive request at that server timeout.
  defp query_timeout(opts, limits) do
    case Map.get(limits, "maxQueryTime", 0) do
      0 -> opts
      ns -> Map.put(opts, :timeout_ms, div(ns, 1_000_000))
    end
  end

  defp validate_query_length(limits, start, finish) do
    limit = Map.get(limits, "maxQueryLength", 0)

    cond do
      limit == 0 -> :ok
      start == nil -> {:error, {:invalid_query_limits, "a positive maxQueryLength requires a finite start"}}
      finish - start > limit -> {:error, {:query_length_exceeded, finish - start, limit}}
      true -> :ok
    end
  end

  # Entry limits reject oversized log requests, never silently truncate them.
  # Metric result points and range-selector intervals are separate policies.
  defp query_expression_limits(%AST.LogQuery{}, opts, limits) do
    limit = Map.get(limits, "maxEntriesLimitPerQuery", 0)

    if limit > 0 and opts.limit > limit,
      do:
        {:error,
         {:query_policy_exceeded,
          "max entries limit per query exceeded, limit > max_entries_limit_per_query (#{opts.limit} > #{limit})"}},
      else: :ok
  end

  defp query_expression_limits(ast, _opts, limits),
    do: query_interval_limit(ast, Map.get(limits, "maxQueryInterval", 0))

  defp query_interval_limit(_, 0), do: :ok

  defp query_interval_limit(%AST.RangeAgg{range_ns: range}, limit) when range > limit,
    do: {:error, {:query_policy_exceeded, "[interval] value exceeds limit: [#{range}ns] > [#{limit}ns]"}}

  defp query_interval_limit(%AST.BinaryOp{left: left, right: right}, limit) do
    with :ok <- query_interval_limit(left, limit), do: query_interval_limit(right, limit)
  end

  defp query_interval_limit(%AST.VectorAgg{inner: inner}, limit), do: query_interval_limit(inner, limit)
  defp query_interval_limit(%AST.LabelReplace{inner: inner}, limit), do: query_interval_limit(inner, limit)
  defp query_interval_limit(_, _), do: :ok

  # Each selector must satisfy the policy independently. Pipeline filters and
  # aggregation labels do not supply stream matchers. Loki counts repeated
  # matcher names toward minimumLabelsNumber, but requiredLabels is a set.
  defp query_matcher_limits(%AST.LogQuery{selector: selector}, limits) do
    present = Enum.map(selector.matchers, & &1.name)
    missing = Enum.reject(Map.get(limits, "requiredLabels", []), &(&1 in present))
    minimum = Map.get(limits, "minimumLabelsNumber", 0)
    labels = Enum.join(present, ", ")

    cond do
      missing != [] ->
        {:error,
         {:query_policy_exceeded,
          "stream selector is missing required matchers [#{Enum.join(missing, ", ")}], labels present in the query were [#{labels}]"}}

      length(present) < minimum ->
        {:error,
         {:query_policy_exceeded,
          "stream selector has less label matchers than required: (present: [#{labels}], number_present: #{length(present)}, required_number_label_matchers: #{minimum})"}}

      true ->
        :ok
    end
  end

  defp query_matcher_limits(%AST.BinaryOp{left: left, right: right}, limits) do
    with :ok <- query_matcher_limits(left, limits), do: query_matcher_limits(right, limits)
  end

  defp query_matcher_limits(%AST.RangeAgg{inner: inner}, limits), do: query_matcher_limits(inner, limits)
  defp query_matcher_limits(%AST.VectorAgg{inner: inner}, limits), do: query_matcher_limits(inner, limits)
  defp query_matcher_limits(%AST.LabelReplace{inner: inner}, limits), do: query_matcher_limits(inner, limits)
  defp query_matcher_limits(_, _), do: :ok

  defp request_query_limits(conn) do
    case get_req_header(conn, "x-loki-query-limits") do
      [] -> {:ok, %{}}
      [header] when byte_size(header) <= 1024 -> parse_query_limits(header)
      _ -> {:error, {:invalid_query_limits, "expected one policy of at most 1024 bytes"}}
    end
  end

  # Keep object pairs: duplicate (including escaped) keys must not silently
  # replace a stricter policy. This intentionally rejects unsupported fields,
  # unlike Loki's permissive Go struct decoder and malformed-header fallback.
  defp parse_query_limits(header) do
    options = [
      object_start: fn _ -> [] end,
      object_push: fn key, value, acc -> [{key, value} | acc] end,
      object_finish: fn acc, old -> {{:object, acc}, old} end
    ]

    case JSON.decode(header, nil, options) do
      {{:object, pairs}, nil, ""} -> parse_query_limit_fields(pairs)
      _ -> {:error, {:invalid_query_limits, "expected a policy object"}}
    end
  rescue
    JSON.DecodeError -> {:error, {:invalid_query_limits, "malformed JSON policy"}}
  end

  defp parse_query_limit_fields(pairs) do
    Enum.reduce_while(pairs, {:ok, %{}}, fn {key, value}, {:ok, limits} ->
      with false <- Map.has_key?(limits, key),
           {:ok, value} <- query_limit_value(key, value) do
        {:cont, {:ok, Map.put(limits, key, value)}}
      else
        true -> {:halt, {:error, {:invalid_query_limits, "duplicate policy field"}}}
        error -> {:halt, error}
      end
    end)
  end

  defp query_limit_value(key, value) when key in ["maxQueryLength", "maxQueryInterval", "maxQueryTime"] do
    case query_limit_duration(value) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:invalid_query_limits, "invalid #{key} duration"}}
    end
  end

  defp query_limit_value(key, value)
       when key in ["maxEntriesLimitPerQuery", "minimumLabelsNumber"] and is_integer(value) and value >= 0 and
              value <= 9_223_372_036_854_775_807, do: {:ok, value}

  defp query_limit_value(key, _) when key in ["maxEntriesLimitPerQuery", "minimumLabelsNumber"],
    do: {:error, {:invalid_query_limits, "invalid #{key} integer"}}

  defp query_limit_value("requiredLabels", value) when is_list(value) do
    if Enum.all?(value, &is_binary/1),
      do: {:ok, Enum.uniq(value)},
      else: {:error, {:invalid_query_limits, "invalid requiredLabels string array"}}
  end

  defp query_limit_value("requiredLabels", _),
    do: {:error, {:invalid_query_limits, "invalid requiredLabels string array"}}

  defp query_limit_value(_, _), do: {:error, {:invalid_query_limits, "unsupported policy field"}}

  # Prometheus model.Duration grammar used by the pinned Loki header: ordered,
  # unrepeated integer y/w/d/h/m/s/ms components, or a bare zero. Quantity owns
  # bounded int64 arithmetic; do not use step's float-seconds parser here.
  defp query_limit_duration("0"), do: {:ok, 0}

  defp query_limit_duration(text) when is_binary(text) and byte_size(text) in 1..128 do
    with true <-
           Regex.match?(
             ~r/\A(?:[0-9]+y)?(?:[0-9]+w)?(?:[0-9]+d)?(?:[0-9]+h)?(?:[0-9]+m)?(?:[0-9]+s)?(?:[0-9]+ms)?\z/,
             text
           ),
         {:ok, duration} <- Quantity.duration_literal(text) do
      {:ok, duration}
    else
      _ -> :error
    end
  end

  defp query_limit_duration(_), do: :error

  defp tenant_from(conn) do
    case Plug.Conn.get_req_header(conn, "x-scope-orgid") do
      [t | _] when is_binary(t) and t != "" -> t
      _ -> @default_tenant
    end
  end

  # -- Error rendering -------------------------------------------------------

  defp render_error(conn, {:error, {:missing_param, name}}) do
    error_json(conn, :bad_request, "missing_param", name)
  end

  defp render_error(conn, {:error, {:invalid_query_parameter, name}}),
    do: error_json(conn, :bad_request, "invalid_parameter", name)

  defp render_error(conn, {:error, {:http_parameter_error, _name, message}}),
    do: error_json(conn, :bad_request, "invalid_parameter", message)

  defp render_error(conn, {:error, {:invalid_query_limits, reason}}),
    do: error_json(conn, :bad_request, "invalid_parameter", "X-Loki-Query-Limits: " <> reason)

  defp render_error(conn, {:error, {:query_policy_exceeded, reason}}),
    do: error_json(conn, :bad_request, "query_limit", reason)

  defp render_error(conn, {:error, {:query_length_exceeded, length, limit}}),
    do:
      error_json(
        conn,
        :bad_request,
        "query_limit",
        "the query time range exceeds the limit (query length: #{length}ns, limit: #{limit}ns)"
      )

  defp render_error(conn, {:error, :label_matchers_only}),
    do: error_json(conn, :bad_request, "invalid_parameter", "only label matchers are supported")

  defp render_error(conn, {:error, {:parse_error, reason}}) do
    error_json(conn, :bad_request, "parse_error", inspect(reason))
  end

  defp render_error(conn, {:error, reason}) when reason in [:missing_token, :invalid_token, :unknown_tenant] do
    conn |> put_status(:unauthorized) |> json(%{"status" => "error", "error" => to_string(reason)})
  end

  defp render_error(conn, {:error, :forbidden}),
    do: conn |> put_status(:forbidden) |> json(%{"status" => "error", "error" => "forbidden"})

  defp render_error(conn, {:error, :auth_unavailable}),
    do: conn |> put_status(:service_unavailable) |> json(%{"status" => "error", "error" => "auth_unavailable"})

  defp render_error(conn, {:error, reason})
       when reason in [
              :query_overloaded,
              :query_timeout,
              :query_sample_limit,
              :query_scan_limit,
              :query_resource_limit,
              :query_result_limit,
              :query_work_limit,
              :query_intermediate_limit,
              :query_execution_failed
            ], do: render_query_error(conn, reason)

  defp render_error(conn, {:error, _reason}),
    do: error_json(conn, :service_unavailable, "storage_unavailable", "Storage is unavailable.")

  defp render_query_error(conn, :query_overloaded),
    do: error_json(conn, :too_many_requests, "query_overloaded", "Query capacity is busy.")

  defp render_query_error(conn, :query_timeout),
    do: error_json(conn, :gateway_timeout, "query_timeout", "Query timed out.")

  defp render_query_error(conn, reason) when reason in [:query_execution_failed, :query_resource_limit],
    do: error_json(conn, :internal_server_error, "query_failed", "Query execution failed.")

  defp render_query_error(conn, reason)
       when reason in [
              :query_scan_limit,
              :query_sample_limit,
              :query_result_limit,
              :query_work_limit,
              :query_intermediate_limit
            ] do
    message =
      case QueryLimit.describe(QueryLimit.take()) do
        nil -> "Query exceeded its resource budget."
        detail -> "Query exceeded its resource budget: #{detail}."
      end

    error_json(conn, :unprocessable_entity, "query_limit", message)
  end

  defp render_query_error(conn, {:storage_error, _}),
    do: error_json(conn, :service_unavailable, "storage_unavailable", "Storage is unavailable.")

  defp render_query_error(conn, reason) when reason in [:object_store_unavailable, :storage_unavailable],
    do: error_json(conn, :service_unavailable, "storage_unavailable", "Storage is unavailable.")

  defp render_query_error(conn, :sort_grouping_not_allowed),
    do: error_json(conn, :bad_request, "parse_error", "sort and sort_desc doesn't allow grouping by")

  defp render_query_error(conn, :missing_topk_parameter),
    do: error_json(conn, :bad_request, "evaluation_failed", "parameter required for operation topk")

  defp render_query_error(conn, :invalid_aggregation_parameter),
    do: error_json(conn, :bad_request, "evaluation_failed", "invalid parameter")

  defp render_query_error(conn, {:missing_unwrap, operation}),
    do: error_json(conn, :bad_request, "evaluation_failed", "invalid aggregation #{operation} without unwrap")

  defp render_query_error(conn, :many_to_many_matching) do
    error_json(
      conn,
      :bad_request,
      "evaluation_failed",
      "multiple matches for labels: many-to-one matching must be explicit (group_left/group_right)"
    )
  end

  defp render_query_error(conn, {:many_to_many_matching, side}) when side in [:left, :right] do
    error_json(
      conn,
      :bad_request,
      "evaluation_failed",
      "found duplicate series on the #{side} hand-side;many-to-many matching not allowed: matching labels must be unique on one side"
    )
  end

  defp render_query_error(conn, reason), do: error_json(conn, :bad_request, "evaluation_failed", inspect(reason))

  defp error_json(conn, status, code, message) do
    conn
    |> put_status(status)
    |> json(%{"status" => "error", "error" => code, "message" => message})
  end
end
