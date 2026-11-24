defmodule Tuist.Pulse do
  @moduledoc """
  Authorized, read-only queries against one server-configured Pulse database.

  String-keyed parameters accept `query`, `range` (15m, 1h, 6h, 24h), `search`,
  `page` (default 1), `page_size` (1..100, default 20), `sort_by`, `sort_order`
  (asc/desc), and an ISO8601 `end_at` (normalized to inclusive UTC seconds).
  Metrics sort by name/value; logs by timestamp/service/level/message/trace_id;
  traces by timestamp/service/name/duration_ms/trace_id; errors by
  last_seen/first_seen/events/accounts/title/service/level. Missing measurements
  sort last. Metrics accept PromQL; log bodies, span names and error issue titles
  accept literal, case-insensitive text (`*` selects all). Trace rows represent
  individual spans; error rows are issues (`Tuist.Pulse.Errors`).

  Service filters apply to every signal, level to logs and errors, and
  environment to errors, where it selects events before issues are grouped. Each has an optional
  `_op`: eq (default, case-sensitive), contains or not_contains
  (case-insensitive literal). Filters are ANDed and empty values ignored. Search
  is a literal case-insensitive projected-row search. All filtering and sorting
  precedes pagination. Rows, series and metadata use string keys; result
  envelope keys are atoms. Series follow the metric page.

  Logs and traces inspect up to 100 newest matches, errors the 100 issues seen
  most recently. Filtering, sorting and
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
  alias Tuist.KeyValueStore
  alias Tuist.Pulse.Errors
  alias Tuist.Pulse.Explore
  alias Tuist.Pulse.SQL
  alias Tuist.Pulse.Table
  alias Tuist.Tasks

  @ranges %{"15m" => 900, "1h" => 3600, "6h" => 21_600, "24h" => 86_400}
  @signals ~w(metrics logs traces errors)
  @limit 100
  @points 361

  def default_query("metrics"), do: "up"
  def default_query(signal) when signal in ~w(logs traces errors), do: "*"
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

  @doc """
  Forwards a Sentry envelope, posted to the API by one of the enrolled
  account's producers (see `available?/1`), to Pulse's Sentry endpoint and
  returns Pulse's status, body and allowlisted rate-limit response headers.

  Pulse's endpoint is internal to the cluster, so the server writes as the
  write-only identity in its own `sentry_pulse_dsn` (the one its web
  instances copy their errors with). `service` names the producer, as the
  service segment of a Pulse DSN does, and `project_id` is passed through.
  Only `content-type` and `content-encoding` of `headers` are forwarded.
  """
  def forward_sentry_envelope(service, project_id, body, headers) do
    with {:ok, writer} <- sentry_writer() do
      request =
        Req.new(
          method: :post,
          url: "#{writer.base_url}/v1/sentry/#{service}/api/#{project_id}/envelope/",
          headers: [
            {"x-sentry-auth", "Sentry sentry_version=7, sentry_key=#{writer.key}, sentry_secret=#{writer.secret}"}
            | Enum.filter(headers, fn {name, _} -> name in ["content-type", "content-encoding"] end)
          ],
          body: body,
          compressed: false,
          decode_body: false,
          redirect: false,
          retry: false,
          receive_timeout: 10_000,
          connect_options: [timeout: 5_000]
        )

      case Req.request(request) do
        {:ok, %Req.Response{status: status, body: body} = response} ->
          headers =
            for name <- ["retry-after", "x-sentry-rate-limits"],
                values = Req.Response.get_header(response, name),
                values != [],
                do: {name, Enum.join(values, ", ")}

          {:ok, status, body, headers}

        {:error, _reason} ->
          {:error, :unavailable}
      end
    end
  end

  @doc """
  Whether Pulse takes the telemetry of Tuist's own clients, such as Luft:
  it belongs to the configured Pulse account and follows that account's
  enrollment (`available?/1`), read at most once a minute per node.
  """
  def own_telemetry? do
    # Every running client asks once a minute; enrollment changes rarely, so
    # each node may answer from a minute-old reading.
    case Keyword.get(Environment.pulse_config(), :account_id) do
      id when is_integer(id) and id > 0 ->
        KeyValueStore.get_or_update([__MODULE__, :own_telemetry, id], [ttl: to_timeout(minute: 1)], fn ->
          case Accounts.get_account_by_id(id) do
            {:ok, account} -> available?(account)
            {:error, :not_found} -> false
          end
        end)

      _ ->
        false
    end
  end

  @doc """
  Forwards `body`, a protobuf OTLP export request for `signal` (`traces`,
  `logs` or `metrics`) that its producer's policy already confined (such as
  `Tuist.Pulse.LuftTelemetry`), to Pulse's OTLP endpoint, into the tables the
  environment's collectors write, as the server's write-only writer (see
  `forward_sentry_envelope/4`). Returns Pulse's status and protobuf body.
  """
  def forward_otlp(signal, body) when signal in ~w(traces logs metrics) and is_binary(body) do
    with {:ok, writer} <- sentry_writer() do
      tables =
        case signal do
          "traces" -> [{"x-pulse-pipeline-name", "pulse_trace_v1"}, {"x-pulse-trace-table-name", "opentelemetry_traces"}]
          "logs" -> [{"x-pulse-log-table-name", "opentelemetry_logs"}]
          "metrics" -> []
        end

      request =
        Req.new(
          method: :post,
          url: "#{writer.base_url}/v1/otlp/v1/#{signal}",
          headers: [
            {"authorization", "Basic " <> Base.encode64("#{writer.key}:#{writer.secret}")},
            {"content-type", "application/x-protobuf"},
            {"x-pulse-db-name", "public"} | tables
          ],
          body: body,
          compressed: false,
          decode_body: false,
          redirect: false,
          retry: false,
          receive_timeout: 10_000,
          connect_options: [timeout: 5_000]
        )

      case Req.request(request) do
        {:ok, %Req.Response{status: status, body: body}} -> {:ok, status, body}
        {:error, _reason} -> {:error, :unavailable}
      end
    end
  end

  defp sentry_writer do
    with dsn when is_binary(dsn) <- Environment.sentry_pulse_dsn(),
         %URI{scheme: scheme, host: host, port: port, userinfo: userinfo}
         when scheme in ["http", "https"] and is_binary(host) and is_binary(userinfo) <- URI.parse(dsn),
         [key, secret] <- String.split(userinfo, ":", parts: 2) do
      {:ok, %{base_url: "#{scheme}://#{host}:#{port}", key: key, secret: secret}}
    else
      _ -> {:error, :not_configured}
    end
  end

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
  One error issue, `(service, fingerprint)`, over a window. String-keyed params
  are a required `service`, `range`, an ISO8601 `end_at`, `page` and
  `page_size`, and an optional `environment` filter on events. Returns the
  issue summary, a 60-bucket occurrence series, the latest event with its
  scrubbed payload and one page of events, newest first,
  with pagination `meta`; `:not_found` when the issue has no events in the
  window.
  """
  def error_issue(user, account, fingerprint, params) do
    if authorized?(user, account) do
      with {:ok, service, opts} <- issue_params(fingerprint, params, ~w(service range end_at page page_size environment)),
           {:ok, client} <- credentials() do
        Errors.issue(service, fingerprint, opts, &request(client, "/v1/sql", &1))
      end
    else
      {:error, :forbidden}
    end
  end

  @doc """
  One event of an error issue, with its scrubbed payload. Params are a required
  `service`, `range` and an ISO8601 `end_at`; `:not_found` when the issue has no
  such event in the window.
  """
  def error_event(user, account, fingerprint, event_id, params) do
    if authorized?(user, account) do
      with true <- is_binary(event_id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, event_id),
           {:ok, service, opts} <- issue_params(fingerprint, params, ~w(service range end_at)),
           {:ok, client} <- credentials() do
        Errors.event(service, fingerprint, event_id, opts, &request(client, "/v1/sql", &1))
      else
        false -> {:error, :invalid_params}
        error -> error
      end
    else
      {:error, :forbidden}
    end
  end

  defp issue_params(fingerprint, %{"service" => service} = params, keys)
       when is_binary(fingerprint) and is_binary(service) do
    with true <- Regex.match?(~r/\A[0-9a-f]{64}\z/, fingerprint) and byte_size(service) in 1..4096,
         true <- Enum.all?(Map.keys(params), &(&1 in keys)),
         {:ok, opts} <- Table.validate("errors", Map.delete(params, "service")) do
      {:ok, service, opts}
    else
      _ -> {:error, :invalid_params}
    end
  end

  defp issue_params(_fingerprint, _params, _keys), do: {:error, :invalid_params}

  @doc """
  Fixed aggregate widgets, independent of the table query. String-keyed `range`
  and `widgets`, a nonempty subset of the signal's widget ids (default all), are
  accepted. Values are end-of-window gauges for metrics and full-window
  aggregates for other signals. Points use Unix seconds; duration is milliseconds.
  Each widget's `previous_value` uses the same query over the preceding equal
  window (the gauge at the current window's start for metrics). Missing values
  remain nil, independently in each period; only the current period has points.

  One snapshot is aligned down to the chart step (at most 240 seconds), and each
  node reuses it until the window advances by a step. Log and
  error charts use minute-aligned, nonoverlapping buckets, at least 60 seconds wide and
  at most 360 points. Count totals are the sums of their period's buckets, which
  partition the window exactly; other totals, such as quantiles and distinct
  services, are independent queries. Trace counts are spans, not traces. Duration quantiles are
  approximate.
  """
  def analytics(user, account, signal, params) do
    with true <- authorized?(user, account),
         {:ok, seconds, ids} <- analytics_params(signal, params),
         {:ok, client} <- credentials() do
      step = if signal in ~w(logs errors), do: ceil(seconds / 360 / 60) * 60, else: ceil(seconds / 360)
      now = DateTime.to_unix(DateTime.utc_now(), :second)
      finish = now - rem(now, step)
      window = %{start: finish - seconds, finish: finish, seconds: seconds, step: step}
      previous_window = %{window | start: window.start - seconds, finish: window.start}

      # A duration's gaps come from the span counts of the same buckets.
      computed = if "duration_p95" in ids, do: ["spans" | ids], else: ids
      widgets = Enum.filter(widget_queries(signal), &(elem(&1, 0) in computed))

      # A window advances by its step (up to 240 seconds), and every refresh and
      # viewer of it on a node shares one computation. Telemetry for the newest
      # bucket can still be arriving when the window is first computed, so the
      # result is kept for at most the dashboard's 15-second refresh, which
      # recomputes it as the old refresh did.
      KeyValueStore.get_or_update(
        [__MODULE__, :analytics, account.id, signal, seconds, finish | ids],
        [ttl: to_timeout(second: min(step, 15)), cache_errors: false],
        fn ->
          with {:ok, analytics} <-
                 signal
                 |> analytics_tasks(widgets, client, window, previous_window)
                 |> Tasks.parallel_tasks(max_concurrency: 3)
                 |> widget_results(signal, widgets, window)
                 |> analytics_widgets(signal) do
            {:ok, %{analytics | widgets: Enum.filter(analytics.widgets, &(&1.id in ids))}}
          end
        end
      )
    else
      false -> {:error, :forbidden}
      error -> error
    end
  end

  defp analytics_tasks("metrics", _widgets, client, window, _previous_window) do
    [fn -> metric_counts(client, window) end]
  end

  # One SQL query per period computes every widget, so each window is scanned
  # once instead of once per widget, and all periods run concurrently. Counts
  # need only one scan of both periods (`SQL.periods/5`).
  defp analytics_tasks(signal, widgets, client, window, previous_window) do
    ids = Enum.map(widgets, &elem(&1, 0))
    request = &request(client, "/v1/sql", &1)

    if SQL.counts?(signal, ids),
      do: [fn -> SQL.periods(signal, ids, window, previous_window, request) end],
      else: aggregate_tasks(signal, ids, window, previous_window, request)
  end

  defp aggregate_tasks(signal, ids, window, previous_window, request) do
    Enum.map([{:instant, window}, {:range, window}, {:instant, previous_window}], fn {mode, window} ->
      fn -> SQL.aggregate(signal, ids, mode, window, request) end
    end)
  end

  # A Prometheus range evaluates the same instant expression at both aligned
  # endpoints. Reuse those observations instead of scanning the source again for
  # each gauge. An absent endpoint stays missing, never carried forward.
  defp widget_results([{:ok, points, warnings}], "metrics", widgets, window) do
    Enum.flat_map(widgets, fn {id, unit} ->
      [
        {:ok, {id, unit, :instant, metric_endpoint(points[id], window.finish), warnings}},
        {:ok, {id, unit, :range, points[id], []}},
        {:ok, {id, unit, :previous, metric_endpoint(points[id], window.start), []}}
      ]
    end)
  end

  defp widget_results([{:ok, current, warnings}, {:ok, points, _}, {:ok, previous, _}], _signal, widgets, _window) do
    Enum.flat_map(widgets, fn {id, unit} ->
      [
        {:ok, {id, unit, :instant, current[id], warnings}},
        {:ok, {id, unit, :range, points[id], []}},
        {:ok, {id, unit, :previous, previous[id], []}}
      ]
    end)
  end

  defp widget_results([{:ok, current, points, previous}], signal, widgets, window),
    do: widget_results([{:ok, current, []}, {:ok, points, []}, {:ok, previous, []}], signal, widgets, window)

  defp widget_results(results, _signal, _widgets, _window), do: Enum.filter(results, &match?({:error, _}, &1))

  defp metric_endpoint(points, time) do
    Enum.find_value(points, fn [timestamp, value] -> if timestamp == time, do: value end)
  end

  # One count_values query yields every metric widget: per step, its series
  # count the targets reporting each value of `up`. Reporting is their sum,
  # healthy the count reporting 1 and unhealthy the count reporting 0, which is
  # zero rather than missing at a step where other values were reported. This
  # scans `up` once per load instead of once per widget.
  @metric_widgets [{"reporting", :any}, {"healthy", 1.0}, {"unhealthy", 0.0}]

  defp metric_counts(client, window) do
    params = [query: ~s|count_values("value", up)|, start: window.start, end: window.finish, step: window.step]

    with {:ok, body} <- request(client, "/api/v1/query_range", params),
         {:ok, warnings} <- warnings(body),
         {:ok, series} <- value_series(body, window) do
      times = series |> Enum.flat_map(fn {_, counts} -> Map.keys(counts) end) |> Enum.uniq() |> Enum.sort()

      count = fn value, time ->
        series |> Enum.filter(&(value in [:any, elem(&1, 0)])) |> Enum.map(&Map.get(elem(&1, 1), time, 0)) |> Enum.sum()
      end

      points =
        Map.new(@metric_widgets, fn {id, value} ->
          {id, Enum.map(times, &[&1, count.(value, &1)])}
        end)

      {:ok, points, warnings}
    end
  end

  # A count_values result has one series per distinct value of `up`, normally
  # just 0 and 1. More than @limit series, or two for the same value, is a
  # malformed response, never a truncated one.
  defp value_series(%{"status" => "success", "data" => %{"resultType" => "matrix", "result" => series}}, window)
       when is_list(series) and length(series) <= @limit do
    with {:ok, series} <- collect(series, &value_counts(&1, window)) do
      if length(Enum.uniq_by(series, &elem(&1, 0))) == length(series),
        do: {:ok, series},
        else: {:error, :malformed_response}
    end
  end

  defp value_series(_body, _window), do: {:error, :malformed_response}

  defp value_counts(%{"metric" => %{"value" => label}, "values" => values}, window)
       when is_binary(label) and is_list(values) and length(values) <= @points do
    value =
      case Float.parse(label) do
        {number, ""} -> number
        _ -> {:other, label}
      end

    with {:ok, counts} <- collect(values, &value_count(&1, window)),
         true <- length(Enum.uniq_by(counts, &hd/1)) == length(counts) do
      {:ok, {value, Map.new(counts, fn [time, count] -> {time, count} end)}}
    end
  end

  defp value_counts(_series, _window), do: :error

  # Points fall on the range's step grid, so the merged series stay within
  # @points steps; a count is a whole number of targets, which Pulse formats as
  # a float ("2.0") and Prometheus as an integer ("2").
  defp value_count([time, count], window) when is_number(time) and is_binary(count) do
    with true <- time == trunc(time) and time >= window.start and time <= window.finish,
         true <- rem(trunc(time) - window.start, window.step) == 0,
         {count, ""} when count >= 0 and count == trunc(count) <- Float.parse(count) do
      {:ok, [trunc(time), trunc(count)]}
    end
  end

  defp value_count(_point, _window), do: :error

  defp analytics_params(signal, params) when signal in @signals and is_map(params) do
    range = Map.get(params, "range", "1h")
    available = Enum.map(widget_queries(signal), &elem(&1, 0))
    ids = Map.get(params, "widgets", available)

    if Enum.all?(Map.keys(params), &(&1 in ~w(range widgets))) and is_binary(range) and Map.has_key?(@ranges, range) and
         is_list(ids) and ids != [] and Enum.all?(ids, &(&1 in available)),
       do: {:ok, Map.fetch!(@ranges, range), ids},
       else: {:error, :invalid_params}
  end

  defp analytics_params(_signal, _params), do: {:error, :invalid_params}

  defp widget_queries("metrics"), do: Enum.map(@metric_widgets, &{elem(&1, 0), :count})

  # Log, trace and error widget SQL is authored server-side from the widget id.
  defp widget_queries("logs"), do: [{"entries", :count}, {"errors", :count}, {"warnings", :count}]
  defp widget_queries("traces"), do: [{"spans", :count}, {"errors", :count}, {"duration_p95", :milliseconds}]
  defp widget_queries("errors"), do: [{"events", :count}, {"fatal", :count}, {"services", :count}]

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
        # span counts of the same period and bucket as evidence.
        widgets = if signal == "traces", do: trace_duration_gaps(widgets), else: widgets
        warnings = Enum.flat_map(results, fn {:ok, {_, _, _, _, warnings}} -> warnings end)
        {:ok, %{widgets: widgets, warnings: warnings |> Enum.uniq() |> Enum.take(@limit)}}

      error ->
        error
    end
  end

  defp scale(nil, _factor), do: nil
  defp scale(number, factor), do: number * factor

  defp trace_duration_gaps(widgets) do
    case {Enum.find(widgets, &(&1.id == "spans")), Enum.find(widgets, &(&1.id == "duration_p95"))} do
      {%{} = spans, %{} = duration} ->
        Enum.map(widgets, &if(&1.id == "duration_p95", do: duration_gaps(spans, duration), else: &1))

      _ ->
        widgets
    end
  end

  defp duration_gaps(spans, duration) do
    counts = Map.new(spans.points, fn [timestamp, count] -> {timestamp, count} end)

    points =
      Enum.map(duration.points, fn [timestamp, value] ->
        [timestamp, if(is_number(counts[timestamp]) and counts[timestamp] > 0, do: value)]
      end)

    value = if is_number(spans.value) and spans.value > 0, do: duration.value
    previous_value = if is_number(spans.previous_value) and spans.previous_value > 0, do: duration.previous_value
    %{duration | value: value, previous_value: previous_value, points: points}
  end

  defp credentials do
    config = Environment.pulse_config()
    url = Keyword.get(config, :base_url)
    token = Keyword.get(config, :token)

    if valid_url?(url) and header?(token),
      do: {:ok, %{base_url: String.trim_trailing(url, "/"), token: token}},
      else: {:error, :not_configured}
  end

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
      case signal do
        "metrics" ->
          with {:ok, body} <- request(client, "/api/v1/query", query: opts.query, time: opts.finish),
               do: normalize(body)

        "errors" ->
          Errors.issues(opts, &request(client, "/v1/sql", &1))

        _ ->
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
  defp complete_result(signal, %{rows: rows}) when signal in ~w(logs traces errors) and length(rows) > @limit,
    do: {:error, :query_result_limit}

  defp complete_result(_, %{rows: rows}) when length(rows) > 5000, do: {:error, :query_result_limit}
  defp complete_result(_, _), do: :ok

  # Every Pulse signal lives in its `public` database, selected by Pulse's
  # x-pulse-db-name header.
  defp request(client, path, params) do
    # Pulse serves its Prometheus-compatible API under /v1/prometheus.
    path = if String.starts_with?(path, "/api/v1/"), do: "/v1/prometheus" <> path, else: path

    request =
      Req.new(
        method: :get,
        url: client.base_url <> path,
        auth: {:basic, "dashboard:" <> client.token},
        headers: [{"accept", "application/json"}, {"x-pulse-db-name", "public"}],
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
      {:ok, %Req.Response{status: status}} -> {:error, status_error(status)}
      {:error, %Req.TransportError{reason: :timeout}} -> {:error, :timeout}
      {:error, _reason} -> {:error, :unavailable}
    end
  end

  defp status_error(status) when status in [400, 422], do: :invalid_query
  defp status_error(429), do: :rate_limited
  # Pulse answers 408 when a query outlives its HTTP timeout; a proxy answers 504.
  defp status_error(status) when status in [408, 504], do: :timeout
  defp status_error(_status), do: :upstream_error

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
