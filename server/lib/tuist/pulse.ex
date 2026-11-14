defmodule Tuist.Pulse do
  @moduledoc """
  Authorized, read-only queries against one server-configured Pulse database.

  String-keyed parameters accept `query`, `range` (15m, 1h, 6h, 24h), `search`,
  `page` (default 1), `page_size` (1..100, default 20), `sort_by`, `sort_order`
  (asc/desc), and an ISO8601 `end_at` (normalized to inclusive UTC seconds).
  Metrics sort by name/value; logs by timestamp/service/level/message/trace_id;
  traces by timestamp/service/name/duration_ms/trace_id. Missing measurements
  sort last. Metrics accept PromQL; log bodies and span names accept literal,
  case-insensitive text (`*` selects all). Trace rows represent individual spans.

  Service filters apply to every signal and level to logs. Each has an optional
  `_op`: eq (default, case-sensitive), contains or not_contains
  (case-insensitive literal). Filters are ANDed and empty values ignored. Search
  is a literal case-insensitive projected-row search. All filtering and sorting
  precedes pagination. Rows, series and metadata use string keys; result
  envelope keys are atoms. Series follow the metric page.

  Logs and traces inspect up to 100 newest matches. Filtering, sorting and
  table totals cover only returned results, not the complete time window.
  Upstream warnings are preserved without generating a result-limit warning.
  Metric tables evaluate an instant snapshot at end_at, not a
  historical grid; analytics provide history. Metrics allow at most 5000 series
  and 361 points per series;
  oversized metric cohorts fail whole. HTTP bodies cap at 8 MiB before JSON
  decoding.
  Pinned time bounds are not an ingestion watermark: later ingestion/retention
  can change a subsequent numbered page's cohort. No snapshot state is retained
  on Tuist replicas.

  Log/trace timestamps retain Unix nanoseconds as strings; metric points are
  Unix seconds. `analytics/4` keeps its independent aggregate contract.
  """

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.Pulse.Explore
  alias Tuist.Pulse.SQL
  alias Tuist.Pulse.Table
  alias Tuist.Tasks

  @ranges %{"15m" => 900, "1h" => 3600, "6h" => 21_600, "24h" => 86_400}
  @signals ~w(metrics logs traces)
  @limit 100
  @points 361

  def default_query("metrics"), do: "up"
  def default_query(signal) when signal in ~w(logs traces), do: "*"
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

  @doc """
  Structured, read-only exploration for agents. Operations: `:metrics`
  (instant or range PromQL), `:labels` (label names, or one label's values with
  counts for logs and traces), `:logs` and `:traces` (filtered newest, oldest or
  slowest matches, at most 100) and `:trace` (one trace's spans, at most 1000).
  See `Tuist.Pulse.Explore` for parameters. Windows reuse the table's 15m, 1h,
  6h and 24h ranges ending at `end_at`; range queries have at most 361 points
  per series and 5000 series.
  """
  def explore(user, account, operation, params) do
    with true <- authorized?(user, account),
         {:ok, opts} <- Explore.validate(operation, params),
         {:ok, client} <- credentials() do
      if operation == :metrics,
        do: explore_metrics(opts, client),
        else: Explore.run(operation, opts, &request(client, &1, &2))
    else
      false -> {:error, :forbidden}
      error -> error
    end
  end

  defp explore_metrics(opts, client) do
    {path, params} =
      if opts.type == "range",
        do: {"/api/v1/query_range", [query: opts.query, start: opts.start, end: opts.finish, step: opts.step]},
        else: {"/api/v1/query", [query: opts.query, time: opts.finish]}

    with {:ok, body} <- request(client, path, params),
         {:ok, result} <- normalize(body),
         :ok <- complete_result("metrics", result) do
      {:ok,
       %{
         type: opts.type,
         series: Enum.sort_by(result.series, & &1["name"]),
         warnings: result.warnings,
         step: opts.step,
         start_at: opts.start_at,
         end_at: opts.end_at
       }}
    end
  end

  @doc """
  Fixed aggregate widgets, independent of the table query. Only string-keyed
  `range` is accepted. Values are end-of-window gauges for metrics and full-window
  aggregates for other signals. Points use Unix seconds; duration is milliseconds.
  Each widget's `previous_value` uses the same query over the preceding equal
  window (the gauge at the current window's start for metrics). Missing values
  remain nil, independently in each period; only the current period has points.

  One snapshot is aligned down to the chart step (at most 240 seconds). Log
  charts use minute-aligned, nonoverlapping buckets, at least 60 seconds wide and
  at most 360 points. Full-window totals are independent queries, never sums of
  chart buckets. Trace counts are spans, not traces. Duration quantiles are
  approximate.
  """
  def analytics(user, account, signal, params) do
    with true <- authorized?(user, account),
         {:ok, seconds} <- analytics_range(signal, params),
         {:ok, client} <- credentials() do
      step = if signal == "logs", do: ceil(seconds / 360 / 60) * 60, else: ceil(seconds / 360)
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

  defp analytics_sample(client, "metrics", {id, query, unit}, :range, window) do
    params = [query: query, start: window.start, end: window.finish, step: window.step]

    with {:ok, body} <- request(client, "/api/v1/query_range", params),
         {:ok, warnings} <- warnings(body),
         {:ok, points} <- metric_points(body),
         {:ok, points} <- aggregate_points(points, window) do
      {:ok, {id, unit, :range, points, warnings}}
    end
  end

  defp analytics_sample(client, signal, {id, unit}, period, window) do
    mode = if period == :previous, do: :instant, else: period

    with {:ok, values, warnings} <- SQL.aggregate(signal, id, mode, window, &request(client, "/v1/sql", &1)) do
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

  # Log and trace widget SQL is authored by Tuist.Pulse.SQL from the id.
  defp widget_queries("logs"), do: [{"entries", :count}, {"errors", :count}, {"warnings", :count}]
  defp widget_queries("traces"), do: [{"spans", :count}, {"errors", :count}, {"duration_p95", :milliseconds}]

  defp metric_points(%{"status" => "success", "data" => %{"resultType" => "matrix", "result" => []}}), do: {:ok, []}

  defp metric_points(%{"status" => "success", "data" => %{"resultType" => "matrix", "result" => [%{"values" => values}]}})
       when is_list(values) and length(values) <= @points do
    collect(values, fn
      [timestamp, value] when is_number(timestamp) and timestamp >= 0 ->
        with {:ok, number} <- analytics_number(value), do: {:ok, [timestamp, number]}

      _ ->
        :error
    end)
  end

  defp metric_points(_body), do: {:error, :malformed_response}

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

  defp aggregate_points(points, window) do
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

        # A duration without spans is not a measured zero duration; use the
        # independently queried span counts as evidence.
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
    # Pulse's database name, sent as x-greptime-db-name.
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

  defp execute(signal, opts, client) do
    result =
      if signal == "metrics" do
        with {:ok, body} <- request(client, "/api/v1/query", query: opts.query, time: opts.finish),
             do: normalize(body)
      else
        SQL.query(signal, opts, &request(client, "/v1/sql", &1))
      end

    with {:ok, result} <- result,
         :ok <- complete_result(signal, result) do
      {rows, meta} = Table.page(result.rows, opts)

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

  defp request(client, path, params) do
    with {:ok, token} <- token(client.token_file, client.token),
         true <- header?(token) do
      do_request(%{client | token: token}, path, params)
    else
      _ -> {:error, :not_configured}
    end
  end

  defp do_request(client, path, params) do
    # Pulse serves its Prometheus-compatible API under /v1/prometheus.
    path = if String.starts_with?(path, "/api/v1/"), do: "/v1/prometheus" <> path, else: path

    request =
      Req.new(
        method: :get,
        url: client.base_url <> path,
        auth: {:basic, "dashboard:" <> client.token},
        headers: [{"accept", "application/json"}, {"x-greptime-db-name", client.tenant}],
        params: params,
        compressed: false,
        into: &bounded_body/2,
        redirect: false,
        retry: false,
        receive_timeout: 30_000,
        connect_options: [timeout: 10_000]
      )

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

  defp normalize(body) do
    with {:ok, warnings} <- warnings(body),
         {:ok, rows, series} <- results(body) do
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

  defp results(%{"status" => "success", "data" => %{"resultType" => "scalar", "result" => value}}) do
    results(%{
      "status" => "success",
      "data" => %{"resultType" => "vector", "result" => [%{"metric" => %{}, "value" => value}]}
    })
  end

  defp results(%{"status" => "success", "data" => %{"resultType" => "vector", "result" => entries}})
       when is_list(entries) do
    entries =
      Enum.map(entries, fn
        %{"metric" => labels, "value" => value} -> %{"metric" => labels, "values" => [value]}
        _ -> nil
      end)

    results(%{"status" => "success", "data" => %{"resultType" => "matrix", "result" => entries}})
  end

  defp results(%{"status" => "success", "data" => %{"resultType" => "matrix", "result" => entries}})
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

  defp results(_body), do: {:error, :malformed_response}

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
end
