defmodule Tuist.Pulse do
  @moduledoc """
  Authorized, read-only queries against one server-configured Pulse tenant.

  String-keyed parameters accept `query`, `range` (15m, 1h, 6h, 24h), `search`,
  `page` (default 1), `page_size` (1..100, default 20), `sort_by`, `sort_order`
  (asc/desc), and an ISO8601 `end_at` (normalized to inclusive UTC seconds).
  Metrics sort by name/value; logs by timestamp/service/level/message/trace_id;
  traces by timestamp/service/name/duration_ms/trace_id; issues by
  last_seen_ns/first_seen_ns/count/title/service/project/issue_id. Missing
  measurements sort last. Native expressions apply to metrics/logs/traces;
  error `query` is a literal, case-insensitive title search, defaulting to empty.

  Service filters apply to every signal, level to logs, and project/environment/
  release to errors. Each has an optional `_op`: eq (default, case-sensitive),
  contains or not_contains (case-insensitive literal). Filters are ANDed and
  empty values ignored. Search is a literal case-insensitive projected-row search.
  All filtering and sorting precedes pagination. Rows, series and metadata use
  string keys; result envelope keys are atoms. Series follow the metric page.

  Logs and traces inspect up to 100 native-query matches. When that limit is
  reached, warnings explicitly scope filtering, sorting and totals to returned
  results, not the complete time window. Logs always select newest first before
  local sorting. Metric tables evaluate an instant snapshot at end_at, not a
  historical grid; analytics provide history. Metrics allow at most 5000 series
  and 361 points per series;
  oversized metric cohorts fail whole. HTTP bodies cap at 8 MiB before JSON
  decoding. Native error reads scan at most 5000 occurrences and 32 MiB, collect
  all 2 MiB cursor pages under one snapshot (at most 32 pages), and cap collected
  JSON at 32 MiB.
  Pinned time bounds are not an ingestion watermark: later ingestion/retention
  can change a subsequent numbered page's cohort. Native cursors reject changes
  within a single collection. No snapshot state is retained on Tuist replicas.

  Log/trace/event timestamps retain Unix nanoseconds as strings; issue bounds
  are native integer nanoseconds, metric points Unix seconds. Error details
  allowlist exception fields (10 exceptions, 100 frames each, 4096 characters
  per text field) and bounded, sanitized tags, contexts, extra and modules.
  Locals and request/auth/user payloads are not returned. `analytics/4` keeps
  its independent aggregate contract.
  """

  use Gettext, backend: TuistWeb.Gettext

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.Pulse.Errors
  alias Tuist.Pulse.Table
  alias Tuist.Tasks

  @ranges %{"15m" => 900, "1h" => 3600, "6h" => 21_600, "24h" => 86_400}
  @signals ~w(metrics logs traces errors)
  @limit 100
  @points 361

  def default_query("metrics"), do: "up"
  def default_query("logs"), do: ~s({service_name=~".+"})
  def default_query("traces"), do: "{}"
  def default_query("errors"), do: ""
  def default_query(_signal), do: nil

  def available?(%{id: id} = account) do
    account_id = Keyword.get(Environment.pulse_config(), :account_id)
    is_integer(account_id) and account_id > 0 and id == account_id and FeatureFlags.pulse_enabled?(account)
  end

  def available?(_account), do: false

  def authorized?(nil, _account), do: false

  def authorized?(user, %{organization_id: organization_id} = account) when not is_nil(organization_id) do
    available?(account) and Accounts.owns_account_or_is_member_of_account_organization?(user, account)
  end

  def authorized?(_user, _account), do: false

  def query(user, account, signal, params) do
    with true <- authorized?(user, account),
         {:ok, opts} <- Table.validate(signal, params),
         {:ok, client} <- credentials() do
      execute(signal, opts, client)
    else
      false -> {:error, :forbidden}
      error -> error
    end
  end

  def error_issue(user, account, issue_id, params) do
    with true <- authorized?(user, account),
         :ok <- valid_ids(issue_id),
         {:ok, opts} <- Table.validate("errors", params, :detail),
         {:ok, client} <- credentials() do
      Errors.issue(issue_id, opts, &error_call(client, &1, &2))
    else
      false -> {:error, :forbidden}
      error -> error
    end
  end

  def error_event(user, account, issue_id, event_id, params) do
    with true <- authorized?(user, account),
         :ok <- valid_ids(issue_id, event_id),
         {:ok, opts} <- Table.validate("errors", params, :detail),
         {:ok, client} <- credentials() do
      Errors.event(issue_id, event_id, opts, &error_call(client, &1, &2))
    else
      false -> {:error, :forbidden}
      error -> error
    end
  end

  defp valid_ids(issue) do
    if Errors.issue_id?(issue), do: :ok, else: {:error, :invalid_params}
  end

  defp valid_ids(issue, event) do
    if Errors.issue_id?(issue) and Errors.event_id?(event), do: :ok, else: {:error, :invalid_params}
  end

  @doc """
  Fixed aggregate widgets, independent of the table query. Only string-keyed
  `range` is accepted. Values are end-of-window gauges for metrics and full-window
  aggregates for other signals. Points use Unix seconds; duration is milliseconds.
  Each widget's `previous_value` uses the same query over the preceding equal
  window (the gauge at the current window's start for metrics). Missing values
  remain nil, independently in each period; only the current period has points.

  One snapshot is aligned down to the chart step (at most 240 seconds) so Tempo's
  epoch-aligned buckets cannot read outside the selected window. Trace counts are
  spans, not traces. Duration quantiles are Pulse's approximate duration buckets.
  """
  def analytics(user, account, signal, params) do
    with true <- authorized?(user, account),
         {:ok, seconds} <- analytics_range(signal, params),
         {:ok, client} <- credentials() do
      step = ceil(seconds / 360)
      now = DateTime.to_unix(DateTime.utc_now(), :second)
      finish = now - rem(now, step)
      window = %{start: finish - seconds, finish: finish, seconds: seconds, step: step}
      previous_window = %{window | start: window.start - seconds, finish: window.start}

      signal
      |> widget_queries()
      |> Enum.flat_map(&analytics_tasks(client, signal, &1, window, previous_window))
      |> Tasks.parallel_tasks(max_concurrency: 3)
      |> metric_gauges(signal, window)
      |> analytics_widgets(signal)
    else
      false -> {:error, :forbidden}
      error -> error
    end
  end

  defp analytics_tasks(client, signal, widget, window, previous_window) do
    Enum.map(analytics_periods(signal, window, previous_window), fn {period, window} ->
      fn -> analytics_sample(client, signal, widget, period, window) end
    end)
  end

  defp analytics_periods("metrics", window, _previous), do: [{:range, window}]
  defp analytics_periods(_signal, window, previous), do: [{:instant, window}, {:range, window}, {:previous, previous}]

  # A Prometheus range evaluates the same instant expression at both aligned
  # endpoints. Reuse those observations instead of scanning the source three
  # times for each gauge. An absent endpoint stays missing, never carried forward.
  defp metric_gauges(results, "metrics", window) do
    Enum.flat_map(results, fn
      {:ok, {id, unit, :range, points, warnings}} = result ->
        [
          {:ok, {id, unit, :instant, metric_endpoint(points, window.finish), warnings}},
          result,
          {:ok, {id, unit, :previous, metric_endpoint(points, window.start), []}}
        ]

      error ->
        [error]
    end)
  end

  defp metric_gauges(results, _signal, _window), do: results

  defp metric_endpoint(points, time) do
    Enum.find_value(points, fn [timestamp, value] -> if timestamp == time, do: value end)
  end

  defp analytics_sample(client, signal, {id, query, unit}, period, window) do
    mode = if period == :previous, do: :instant, else: period
    {path, params} = analytics_request(signal, id, query, mode, window)

    with {:ok, body} <- request(client, path, params),
         {:ok, values, warnings} <- analytics_result(signal, mode, body, window) do
      {:ok, {id, unit, period, values, warnings}}
    end
  end

  defp analytics_range(signal, params) when signal in @signals and is_map(params) do
    range = Map.get(params, "range", "1h")

    if Enum.all?(Map.keys(params), &(&1 == "range")) and is_binary(range) and Map.has_key?(@ranges, range),
      do: {:ok, Map.fetch!(@ranges, range)},
      else: {:error, :invalid_params}
  end

  defp analytics_range(_signal, _params), do: {:error, :invalid_params}

  defp widget_queries("metrics") do
    [
      {"reporting", "count(up)", :count},
      {"healthy", "sum(up == bool 1)", :count},
      {"unhealthy", "sum(up == bool 0)", :count}
    ]
  end

  defp widget_queries("logs") do
    [
      {"entries", ~s({service_name=~".+"}), :count},
      {"errors", ~s'{service_name=~".+",level=~"(?i)(error|fatal)"}', :count},
      {"warnings", ~s'{service_name=~".+",level=~"(?i)(warning|warn)"}', :count}
    ]
  end

  defp widget_queries("errors") do
    [
      {"events", ~s({error_source="sentry"}), :count},
      {"fatal", ~s'{error_source="sentry",level=~"(?i)fatal"}', :count},
      {"services", ~s({error_source="sentry",service_name=~".+"}), :count}
    ]
  end

  defp widget_queries("traces") do
    [
      {"spans", "{} | count_over_time()", :count},
      {"errors", "{status=error} | count_over_time()", :count},
      {"duration_p95", "{} | quantile_over_time(duration,0.95)", :milliseconds}
    ]
  end

  defp analytics_request("metrics", _id, query, :instant, window),
    do: {"/api/v1/query", [query: query, time: window.finish]}

  defp analytics_request("metrics", _id, query, :range, window),
    do: {"/api/v1/query_range", [query: query, start: window.start, end: window.finish, step: window.step]}

  defp analytics_request("traces", _id, query, mode, window) do
    path = if mode == :instant, do: "/api/metrics/query", else: "/api/metrics/query_range"
    params = [q: query, start: window.start, end: window.finish]
    {path, if(mode == :range, do: params ++ [step: "#{window.step}s"], else: params)}
  end

  defp analytics_request(signal, id, selector, mode, window) do
    duration = if mode == :instant, do: window.seconds, else: window.step
    counts = "count_over_time(#{selector}[#{duration}s])"

    query =
      if signal == "errors" and id == "services",
        do: "count(sum by (service_name) (#{counts}))",
        else: "sum(#{counts})"

    if mode == :instant do
      {"/loki/api/v1/query", [query: query, time: Integer.to_string(window.finish * 1_000_000_000)]}
    else
      # Each point counts (t-step, t], not a sliding full-period window.
      {"/loki/api/v1/query_range",
       [
         query: query,
         start: Integer.to_string((window.start + window.step) * 1_000_000_000),
         end: Integer.to_string(window.finish * 1_000_000_000),
         step: window.step
       ]}
    end
  end

  defp analytics_result(signal, mode, body, window) do
    with {:ok, warnings} <- warnings(body),
         {:ok, values} <- aggregate_values(signal, mode, body),
         {:ok, values} <- aggregate_points(mode, values, window) do
      # Tempo adds a leading interval ending at start. It is outside the
      # requested period, not a truncated part of the selected analytics.
      values =
        if signal == "traces" and mode == :range,
          do: Enum.reject(values, fn [timestamp, _] -> timestamp == window.start end),
          else: values

      {:ok, values, warnings}
    end
  end

  defp aggregate_values("traces", :instant, %{"series" => []}), do: {:ok, nil}
  defp aggregate_values("traces", :instant, %{"series" => [%{"value" => value}]}), do: analytics_number(value)
  defp aggregate_values("traces", :range, %{"series" => []}), do: {:ok, []}

  defp aggregate_values("traces", :range, %{"series" => [%{"samples" => samples}]})
       when is_list(samples) and length(samples) <= @points do
    collect(samples, fn
      %{"timestampMs" => timestamp, "value" => value} when is_binary(timestamp) ->
        with {millis, ""} when millis >= 0 <- Integer.parse(timestamp),
             {:ok, number} <- analytics_number(value),
             do: {:ok, [millis / 1000, number]}

      _ ->
        :error
    end)
  end

  defp aggregate_values(signal, mode, %{"status" => "success", "data" => %{"resultType" => type, "result" => entries}})
       when signal in ~w(metrics logs errors) and is_list(entries) do
    case {mode, type, entries} do
      {:instant, "vector", []} ->
        {:ok, nil}

      {:instant, "vector", [%{"value" => [_timestamp, value]}]} ->
        analytics_number(value)

      {:range, "matrix", []} ->
        {:ok, []}

      {:range, "matrix", [%{"values" => values}]} when is_list(values) and length(values) <= @points ->
        collect(values, fn
          [timestamp, value] when is_number(timestamp) and timestamp >= 0 ->
            with {:ok, number} <- analytics_number(value), do: {:ok, [timestamp, number]}

          _ ->
            :error
        end)

      _ ->
        {:error, :malformed_response}
    end
  end

  defp aggregate_values(_signal, _mode, _body), do: {:error, :malformed_response}

  defp analytics_number(value) when is_number(value), do: {:ok, value}
  defp analytics_number(nil), do: {:ok, nil}
  defp analytics_number(value) when value in ["NaN", "+Inf", "-Inf", "Inf"], do: {:ok, nil}

  defp analytics_number(value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> {:ok, number}
      _ -> {:error, :malformed_response}
    end
  end

  defp analytics_number(_value), do: {:error, :malformed_response}
  defp aggregate_points(:instant, value, _window), do: {:ok, value}

  defp aggregate_points(:range, points, window) do
    points = Enum.sort_by(points, &hd/1)

    if length(Enum.uniq_by(points, &hd/1)) == length(points) and
         Enum.all?(points, fn [timestamp, _] -> timestamp >= window.start and timestamp <= window.finish end) do
      {:ok, points}
    else
      {:error, :malformed_response}
    end
  end

  defp analytics_widgets(results, signal) do
    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        widgets =
          results
          |> Enum.chunk_every(3)
          |> Enum.map(fn [
                           {:ok, {id, unit, :instant, value, _}},
                           {:ok, {id, unit, :range, points, _}},
                           {:ok, {id, unit, :previous, previous_value, _}}
                         ] ->
            factor = if unit == :milliseconds, do: 1000, else: 1

            %{
              id: id,
              unit: unit,
              value: scale(value, factor),
              previous_value: scale(previous_value, factor),
              points: Enum.map(points, fn [timestamp, value] -> [timestamp, scale(value, factor)] end)
            }
          end)

        # Tempo emits zero-valued empty duration buckets. They are not measured
        # zero durations; use the independently queried span counts as evidence.
        widgets = if signal == "traces", do: trace_duration_gaps(widgets), else: widgets
        warnings = Enum.flat_map(results, fn {:ok, {_, _, _, _, warnings}} -> warnings end)
        {:ok, %{widgets: widgets, warnings: warnings |> Enum.uniq() |> Enum.take(@limit)}}

      error ->
        error
    end
  end

  defp scale(nil, _factor), do: nil
  defp scale(number, factor), do: number * factor

  defp trace_duration_gaps([spans, errors, duration]) do
    counts = Map.new(spans.points, fn [timestamp, count] -> {timestamp, count} end)

    points =
      Enum.map(duration.points, fn [timestamp, value] ->
        [timestamp, if(is_number(counts[timestamp]) and counts[timestamp] > 0, do: value)]
      end)

    value = if is_number(spans.value) and spans.value > 0, do: duration.value
    previous_value = if is_number(spans.previous_value) and spans.previous_value > 0, do: duration.previous_value
    [spans, errors, %{duration | value: value, previous_value: previous_value, points: points}]
  end

  defp credentials do
    config = Environment.pulse_config()
    url = Keyword.get(config, :base_url)
    tenant = Keyword.get(config, :tenant)

    with true <- valid_url?(url) and header?(tenant),
         {:ok, token} <- token(Keyword.get(config, :token_file), Keyword.get(config, :token)),
         true <- header?(token) do
      {:ok,
       %{
         base_url: String.trim_trailing(url, "/"),
         tenant: tenant,
         token: token,
         token_file: Keyword.get(config, :token_file)
       }}
    else
      _ -> {:error, :not_configured}
    end
  end

  # Projected secrets rotate independently of the application and are authoritative.
  defp token(path, _token) when is_binary(path) and path != "" do
    case File.read(path) do
      {:ok, contents} -> {:ok, String.trim(contents)}
      _ -> {:error, :not_configured}
    end
  end

  defp token(_path, token), do: {:ok, token}

  defp header?(value) do
    is_binary(value) and byte_size(value) in 1..16_384 and String.valid?(value) and
      Regex.match?(~r/\A[^\s\x00-\x1f\x7f]+\z/u, value)
  end

  defp valid_url?(url) when is_binary(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme, host: host, userinfo: nil, query: nil, fragment: nil}} ->
        scheme in ["https", "http"] and is_binary(host) and host != ""

      _ ->
        false
    end
  end

  defp valid_url?(_url), do: false

  defp execute("errors", opts, client), do: Errors.list(opts, &error_call(client, &1, &2))

  defp execute(signal, opts, client) do
    {path, params} = request_params(signal, opts.query, opts.finish - opts.seconds, opts.finish, opts.seconds)

    with {:ok, body} <- request(client, path, params),
         {:ok, result} <- normalize(signal, body),
         :ok <- complete_result(signal, result) do
      {rows, meta} = Table.page(result.rows, opts)

      result =
        if signal in ~w(logs traces) and length(result.rows) >= @limit do
          warning =
            dgettext(
              "dashboard_pulse",
              "Search reached its 100-result limit. Filters, sorting and totals cover only returned results; narrow the native query or time range."
            )

          %{result | warnings: [warning | result.warnings]}
        else
          result
        end

      series =
        if signal == "metrics",
          do: Enum.map(rows, fn row -> Enum.find(result.series, &(&1["labels"] == row["labels"])) end),
          else: []

      {:ok, Map.put(%{result | rows: rows, series: series}, :meta, meta)}
    end
  end

  # An unexpectedly oversized response still fails rather than escaping bounds.
  defp complete_result(signal, %{rows: rows}) when signal in ~w(logs traces) and length(rows) > @limit,
    do: {:error, :query_result_limit}

  defp complete_result(_, %{rows: rows}) when length(rows) > 5000, do: {:error, :query_result_limit}
  defp complete_result(_, _), do: :ok

  defp error_call(client, tool, args) do
    # Configuration, not user parameters, is the sole tenant authority.
    body = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "tools/call",
      "params" => %{
        "name" => tool,
        "arguments" => Map.put(args, "tenant", client.tenant),
        "_meta" => %{
          "io.modelcontextprotocol/protocolVersion" => "2026-07-28",
          "io.modelcontextprotocol/clientCapabilities" => %{},
          "io.modelcontextprotocol/clientInfo" => %{"name" => "Tuist", "version" => Environment.version()}
        }
      }
    }

    request(client, "/mcp", [],
      method: :post,
      json: body,
      headers: [{"mcp-protocol-version", "2026-07-28"}, {"mcp-method", "tools/call"}, {"mcp-name", tool}]
    )
  end

  defp request(client, path, params, extra \\ []) do
    with {:ok, token} <- token(client.token_file, client.token),
         true <- header?(token) do
      do_request(%{client | token: token}, path, params, extra)
    else
      _ -> {:error, :not_configured}
    end
  end

  defp do_request(client, path, params, extra) do
    request =
      Req.new(
        method: Keyword.get(extra, :method, :get),
        url: client.base_url <> path,
        auth: {:bearer, client.token},
        headers: [{"accept", "application/json"}, {"x-scope-orgid", client.tenant}] ++ Keyword.get(extra, :headers, []),
        params: params,
        compressed: false,
        into: &bounded_body/2,
        redirect: false,
        retry: false,
        receive_timeout: 30_000,
        connect_options: [timeout: 10_000]
      )

    request = if Keyword.has_key?(extra, :json), do: Req.merge(request, json: extra[:json]), else: request

    case Req.request(request) do
      {:ok, %Req.Response{body: :too_large}} -> {:error, :query_result_limit}
      {:ok, %Req.Response{status: 200, body: body}} -> decode_body(body)
      {:ok, %Req.Response{status: status}} when status in [400, 422] -> {:error, :invalid_query}
      {:ok, %Req.Response{status: 429}} -> {:error, :rate_limited}
      {:ok, %Req.Response{}} -> {:error, :upstream_error}
      {:error, %Req.TransportError{reason: :timeout}} -> {:error, :timeout}
      {:error, _reason} -> {:error, :unavailable}
    end
  end

  defp bounded_body({:data, data}, {request, response}) do
    body = response.body || ""

    if byte_size(body) + byte_size(data) <= 8_388_608,
      do: {:cont, {request, %{response | body: body <> data}}},
      else: {:halt, {request, %{response | body: :too_large}}}
  end

  defp decode_body(body) when is_binary(body) and byte_size(body) <= 8_388_608 do
    case JSON.decode(body) do
      {:ok, %{} = decoded} -> {:ok, decoded}
      _ -> {:error, :malformed_response}
    end
  end

  defp decode_body(body) when is_map(body) do
    if byte_size(JSON.encode!(body)) <= 8_388_608, do: {:ok, body}, else: {:error, :query_result_limit}
  end

  defp decode_body(body) when is_binary(body), do: {:error, :query_result_limit}
  defp decode_body(_), do: {:error, :malformed_response}

  defp request_params("metrics", query, _start, finish, _seconds) do
    {"/api/v1/query", [query: query, time: finish]}
  end

  defp request_params("traces", query, start, finish, _seconds) do
    {"/api/search", [q: query, start: start, end: finish, limit: @limit]}
  end

  defp request_params(_signal, query, start, finish, _seconds) do
    {"/loki/api/v1/query_range",
     [
       query: query,
       start: Integer.to_string(start * 1_000_000_000),
       end: Integer.to_string(finish * 1_000_000_000),
       limit: @limit,
       direction: "backward"
     ]}
  end

  defp normalize(signal, body) do
    with {:ok, warnings} <- warnings(body),
         {:ok, rows, series} <- results(signal, body) do
      {:ok, %{rows: rows, series: series, warnings: warnings}}
    end
  end

  defp warnings(body) do
    case Map.get(body, "warnings", []) do
      warnings when is_list(warnings) ->
        if Enum.all?(warnings, &is_binary/1), do: {:ok, Enum.take(warnings, @limit)}, else: {:error, :malformed_response}

      _ ->
        {:error, :malformed_response}
    end
  end

  defp results("metrics", %{"status" => "success", "data" => %{"resultType" => "scalar", "result" => value}}) do
    results("metrics", %{
      "status" => "success",
      "data" => %{"resultType" => "vector", "result" => [%{"metric" => %{}, "value" => value}]}
    })
  end

  defp results("metrics", %{"status" => "success", "data" => %{"resultType" => "vector", "result" => entries}})
       when is_list(entries) do
    entries =
      Enum.map(entries, fn
        %{"metric" => labels, "value" => value} -> %{"metric" => labels, "values" => [value]}
        _ -> nil
      end)

    results("metrics", %{"status" => "success", "data" => %{"resultType" => "matrix", "result" => entries}})
  end

  defp results("metrics", %{"status" => "success", "data" => %{"resultType" => "matrix", "result" => entries}})
       when is_list(entries) do
    with {:ok, series} <- collect(entries, &metric/1) do
      rows =
        Enum.map(series, fn series ->
          point = List.last(series["points"])
          %{"name" => series["name"], "labels" => series["labels"], "value" => if(point, do: List.last(point))}
        end)

      {:ok, rows, series}
    end
  end

  defp results(signal, %{"status" => "success", "data" => %{"resultType" => "streams", "result" => entries}})
       when signal in ~w(logs errors) and is_list(entries) do
    with {:ok, streams} <- collect(entries, &log_stream/1) do
      {:ok, streams |> List.flatten() |> latest(), []}
    end
  end

  defp results("traces", %{"traces" => traces}) when is_list(traces) do
    with {:ok, rows} <- collect(traces, &trace/1), do: {:ok, latest(rows), []}
  end

  defp results(_signal, _body), do: {:error, :malformed_response}

  defp collect(entries, fun) do
    entries
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
      case fun.(entry) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        _ -> {:halt, {:error, :malformed_response}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp metric(%{"metric" => labels, "values" => values}) when is_map(labels) and is_list(values) do
    with true <- Enum.all?(labels, fn {key, value} -> is_binary(key) and is_binary(value) end),
         true <- length(values) <= @points,
         {:ok, points} <- collect(values, &point/1) do
      points = Enum.sort_by(points, &hd/1)

      suffix =
        labels
        |> Map.delete("__name__")
        |> Enum.sort()
        |> Enum.map_join(", ", fn {key, value} -> "#{key}=#{value}" end)

      name = Map.get(labels, "__name__", "") <> if(suffix == "", do: "", else: "{#{suffix}}")
      {:ok, %{"name" => name, "labels" => labels, "points" => points}}
    end
  end

  defp metric(_entry), do: :error

  defp point([timestamp, value]) when is_number(timestamp) and is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> {:ok, [timestamp, number]}
      _ when value in ["NaN", "+Inf", "-Inf", "Inf"] -> {:ok, [timestamp, value]}
      _ -> :error
    end
  end

  defp point(_point), do: :error

  defp log_stream(%{"stream" => labels, "values" => values}) when is_map(labels) and is_list(values) do
    collect(values, &log_row(&1, labels))
  end

  defp log_stream(_stream), do: :error

  defp log_row([timestamp, line | rest], labels) when is_binary(line) do
    with {:ok, timestamp} <- nanoseconds(timestamp) do
      metadata =
        case rest do
          [%{} = metadata] -> metadata
          _ -> %{}
        end

      fields =
        case JSON.decode(line) do
          {:ok, %{} = fields} -> fields
          _ -> %{}
        end

      {:ok,
       %{
         "timestamp" => timestamp,
         "service" => text(labels["service_name"]) || "",
         "level" => text(labels["level"]) || text(labels["severity_text"]) || text(fields["level"]) || "",
         "message" => log_message(line, fields),
         "trace_id" => log_trace_id(metadata, labels, fields)
       }}
    end
  end

  defp log_row(_entry, _labels), do: :error

  defp log_trace_id(metadata, labels, fields) do
    text(metadata["trace_id"]) || text(labels["trace_id"]) || text(fields["trace_id"]) ||
      nested_text(fields, "contexts", "trace", "trace_id") || ""
  end

  defp log_message(line, fields) do
    case JSON.decode(line) do
      {:ok, %{} = event} ->
        text(event["message"]) || nested_text(fields, "logentry", "formatted") ||
          nested_text(fields, "logentry", "message") || exception_message(event) || "Structured log"

      {:ok, _structured} ->
        "Structured log"

      {:error, _reason} ->
        text(line)
    end
  end

  defp exception_message(%{"exception" => %{"values" => values}}) when is_list(values) do
    case List.last(values) do
      %{"type" => type, "value" => value} when is_binary(type) and is_binary(value) -> text(type <> ": " <> value)
      _ -> nil
    end
  end

  defp exception_message(_event), do: nil

  defp nested_text(map, key, child), do: if(is_map(map[key]), do: text(map[key][child]))
  defp nested_text(map, key, child, field), do: if(is_map(map[key]), do: nested_text(map[key], child, field))
  defp text(value) when is_binary(value), do: String.slice(value, 0, 4096)
  defp text(_value), do: nil

  defp trace(%{"traceID" => id, "startTimeUnixNano" => timestamp} = trace) when is_binary(id) and id != "" do
    with {:ok, timestamp} <- nanoseconds(timestamp),
         true <- is_nil(trace["durationMs"]) or is_number(trace["durationMs"]) do
      {:ok,
       %{
         "trace_id" => id,
         "service" => text(trace["rootServiceName"]),
         "name" => text(trace["rootTraceName"]),
         "duration_ms" => trace["durationMs"],
         "timestamp" => timestamp
       }}
    end
  end

  defp trace(_trace), do: :error

  defp nanoseconds(value) when is_integer(value) and value >= 0, do: {:ok, Integer.to_string(value)}

  defp nanoseconds(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number >= 0 -> {:ok, Integer.to_string(number)}
      _ -> :error
    end
  end

  defp nanoseconds(_value), do: :error
  defp latest(rows), do: Enum.sort_by(rows, &String.to_integer(&1["timestamp"]), :desc)
end
