defmodule TuistWeb.ToolchainCacheLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.ChartTypeToggle
  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.ScatterChart
  import TuistWeb.Components.Skeleton
  import TuistWeb.PercentileDropdownWidget
  import TuistWeb.Runs.RanByBadge

  alias Phoenix.LiveView.AsyncResult
  alias Tuist.Utilities.ByteFormatter
  alias Tuist.Utilities.DateFormatter
  alias Tuist.Utilities.ThroughputFormatter
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  @widgets ~w(hit_rate transfer latency throughput)
  @percentiles ~w(avg p99 p90 p50)

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    if project.build_system != socket.assigns.live_action, do: raise(TuistWeb.Errors.NotFoundError)

    {cache_module, cache_id, title, guide, description} = configuration(project.build_system)

    {:ok,
     socket
     |> assign(:cache_module, cache_module)
     |> assign(:cache_id, cache_id)
     |> assign(:cache_guide, guide)
     |> assign(:transport_description, description)
     |> assign(:scatter, AsyncResult.ok(:line))
     |> assign(:head_title, "#{title} · #{account.name}/#{project.name} · Tuist")
     |> assign(OpenGraph.project_image_assigns(project, title: title, fallback: "overview"))}
  end

  def handle_params(_params, uri, socket) do
    params = Query.query_params(uri)
    period_params = Map.take(params, ~w(analytics-date-range analytics-start-date analytics-end-date))
    date = date_selection(socket, params, period_params)
    environment = if params["analytics-environment"] in ~w(local ci), do: params["analytics-environment"], else: "any"
    widget = if params["widget"] in @widgets, do: params["widget"], else: "hit_rate"
    {start_datetime, end_datetime} = date.period
    opts = [start_datetime: start_datetime, end_datetime: DateTime.add(end_datetime, 1, :second)]
    opts = if environment == "any", do: opts, else: Keyword.put(opts, :is_ci, environment == "ci")
    project_id = socket.assigns.selected_project.id
    cache_module = socket.assigns.cache_module
    key = {project_id, opts}

    socket =
      socket
      |> assign(:uri, URI.new!("?" <> URI.encode_query(params)))
      |> assign(:preset, date.preset)
      |> assign(:period, date.period)
      |> assign(:period_params, period_params)
      |> assign(:environment, environment)
      |> assign(:widget, widget)
      |> assign(:cache_opts, opts)
      |> assign(:hit_rate_type, selection(params["hit-rate-type"], @percentiles, "avg"))
      |> assign(:transfer_type, selection(params["transfer-type"], ~w(combined downloads uploads), "combined"))
      |> assign(:latency_type, selection(params["latency-type"], ~w(combined read write), "combined"))
      |> assign(:throughput_type, selection(params["throughput-type"], ~w(combined downloads uploads), "combined"))
      |> assign(:chart_type, if(params["cache-hit-rate-chart-type"] == "scatter", do: "scatter", else: "line"))

    socket =
      if socket.assigns[:analytics_key] == key and !socket.assigns.analytics.failed and
           !socket.assigns.recent_builds.failed do
        socket
      else
        socket
        |> assign(:analytics_key, key)
        |> assign_async(:analytics, fn ->
          analytics = cache_module.hit_rate_analytics(project_id, opts)
          {:ok, %{analytics: Map.put(analytics, :transport, cache_module.io_analytics(project_id, opts))}}
        end)
        |> assign_async(:recent_builds, fn ->
          {:ok, %{recent_builds: cache_module.recent_builds(project_id, Keyword.put(opts, :limit, 50))}}
        end)
      end

    {:noreply, maybe_assign_scatter(socket)}
  end

  def handle_event("select_widget", %{"widget" => widget}, socket) when widget in @widgets,
    do: update_selection(socket, :widget, "widget", widget)

  def handle_event("select_hit_rate_type", %{"type" => type}, socket) when type in @percentiles,
    do: update_selection(socket, :hit_rate_type, "hit-rate-type", type)

  def handle_event("select_transfer_type", %{"type" => type}, socket) when type in ~w(combined downloads uploads),
    do: update_selection(socket, :transfer_type, "transfer-type", type)

  def handle_event("select_latency_type", %{"type" => type}, socket) when type in ~w(combined read write),
    do: update_selection(socket, :latency_type, "latency-type", type)

  def handle_event("select_throughput_type", %{"type" => type}, socket) when type in ~w(combined downloads uploads),
    do: update_selection(socket, :throughput_type, "throughput-type", type)

  def handle_event("select_cache_hit_rate_chart_type", %{"type" => type}, socket) when type in ~w(line scatter),
    do: update_selection(socket, :chart_type, "cache-hit-rate-chart-type", type)

  def handle_event(
        "analytics_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        socket
      ) do
    query = Query.put(socket.assigns.uri.query, "analytics-date-range", preset)

    query =
      if preset == "custom",
        do: query |> Query.put("analytics-start-date", start_date) |> Query.put("analytics-end-date", end_date),
        else: query

    {:noreply, push_patch(socket, to: cache_path(socket, query))}
  end

  defp update_selection(socket, assign, param, value) do
    query = Query.put(socket.assigns.uri.query, param, value)

    {:noreply,
     socket
     |> assign(assign, value)
     |> assign(:uri, URI.new!("?" <> query))
     |> maybe_assign_scatter()
     |> push_event("replace-url", %{url: "?" <> query})}
  end

  defp selection(value, allowed, default), do: if(value in allowed, do: value, else: default)

  defp maybe_assign_scatter(%{assigns: %{widget: "hit_rate", chart_type: "scatter"}} = socket) do
    project_id = socket.assigns.selected_project.id
    opts = socket.assigns.cache_opts
    cache_module = socket.assigns.cache_module
    key = {project_id, opts}

    if socket.assigns[:scatter_key] == key and !socket.assigns.scatter.failed do
      socket
    else
      socket
      |> assign(:scatter_key, key)
      |> assign_async(:scatter, fn ->
        {:ok, %{scatter: {:scatter, project_id |> cache_module.hit_rate_scatter_data(opts) |> scatter_labels()}}}
      end)
    end
  end

  defp maybe_assign_scatter(socket), do: socket

  defp scatter_labels(data) do
    Map.update!(data, :series, fn series ->
      Enum.map(series, fn group ->
        group
        |> Map.put(:name, if(group.name, do: "CI", else: dgettext("dashboard", "Local")))
        |> Map.put(:color, if(group.name, do: "var:noora-chart-p90", else: "var:noora-chart-primary"))
      end)
    end)
  end

  defp scatter_url(point, account, project), do: build_path(point.id, account, project) <> "?tab=cache"

  defp build_path(id, account, %{build_system: :cargo} = project),
    do: ~p"/#{account.name}/#{project.name}/builds/cargo-builds/#{id}"

  defp build_path(id, account, project), do: ~p"/#{account.name}/#{project.name}/builds/mix-builds/#{id}"

  defp recent_build_path(row, account, project) do
    path = build_path(row.build.id, account, project)
    if Map.get(row.cache, :available, true), do: path <> "?tab=cache", else: path
  end

  defp cache_path(%{assigns: %{selected_project: %{build_system: :cargo} = project, selected_account: account}}, query),
    do: ~p"/#{account.name}/#{project.name}/cargo-cache" <> "?" <> query

  defp cache_path(socket, query),
    do: ~p"/#{socket.assigns.selected_account.name}/#{socket.assigns.selected_project.name}/mix-cache" <> "?" <> query

  defp configuration(:cargo) do
    {Tuist.Cargo.Cache, "cargo-cache", dgettext("dashboard", "Cargo Cache"),
     "/en/docs/guides/features/build-insights/rust#cache-measurements",
     dgettext(
       "dashboard_cache",
       "Experimental Cargo cache measurements. Transfer totals use build-wide byte counters. Latency measures recorded per-key index operations, not compilation or artifact transfer time. Throughput uses successful measured CAS transfers only; failed and already-present operations are excluded. Inspection records may be partial."
     )}
  end

  defp configuration(:mix) do
    {Tuist.Mix.Cache, "mix-cache", dgettext("dashboard", "Mix Cache"), "/en/docs/guides/features/cache/elixir",
     dgettext(
       "dashboard",
       "Successful client CAS transfers and local fallback copies, with provenance on each build's task rows. Remote timings measure transfers; local timings include verification and installation. Throughput is bytes divided by operation time. Compilation and linked resources are excluded. CAS Outputs separately shows only Kura-reported remote transfers."
     )}
  end

  defp hit_rate_description(%{build_system: :cargo}) do
    dgettext(
      "dashboard_cache",
      "Average and percentiles of individual build cache hit rates. Hits reuse cached outputs; misses include lookup misses, cold compilations, and verification rebuilds. Prefetches are excluded."
    )
  end

  defp hit_rate_description(_) do
    dgettext(
      "dashboard",
      "Average and percentiles of individual build cache hit rates. Work without a cache lookup is excluded."
    )
  end

  defp build_runs_path(account, %{build_system: :cargo} = project),
    do: ~p"/#{account.name}/#{project.name}/builds/build-runs"

  defp build_runs_path(account, project), do: ~p"/#{account.name}/#{project.name}/builds"

  defp build_command(%{build_system: :cargo}, build), do: "cargo #{build.command}"
  defp build_command(_, _build), do: "mix compile"
  defp build_description(%{build_system: :cargo}, _build), do: nil
  defp build_description(_, build), do: if(build.mix_env not in [nil, ""], do: build.mix_env)

  defp value(nil), do: dgettext("dashboard", "No data")
  defp value(value), do: "#{Float.round(value * 1.0, 1)}%"
  defp percentile_metrics(metrics), do: Map.new(metrics, fn {key, metric} -> {key, value(metric)} end)
  defp selected_metric(metrics, type), do: Map.fetch!(metrics, String.to_existing_atom(type))
  defp percentile_color("avg"), do: "primary"
  defp percentile_color(type), do: type
  defp percentile_title("avg"), do: dgettext("dashboard_cache", "Avg. cache hit rate")
  defp percentile_title("p99"), do: dgettext("dashboard_cache", "p99 cache hit rate")
  defp percentile_title("p90"), do: dgettext("dashboard_cache", "p90 cache hit rate")
  defp percentile_title("p50"), do: dgettext("dashboard_cache", "p50 cache hit rate")
  defp series_name("avg"), do: dgettext("dashboard_cache", "Average")
  defp series_name(type), do: type

  defp trend_label("last-24-hours"), do: dgettext("dashboard_cache", "since yesterday")
  defp trend_label("last-7-days"), do: dgettext("dashboard_cache", "since last week")
  defp trend_label("custom"), do: dgettext("dashboard_cache", "since last period")
  defp trend_label(_), do: dgettext("dashboard_cache", "since last month")

  defp transport_widgets(transfer, latency, throughput) do
    [
      %{
        id: "transfer",
        type: transfer,
        event: "select_transfer_type",
        color: "p50",
        options: ~w(combined downloads uploads)
      },
      %{id: "latency", type: latency, event: "select_latency_type", color: "p90", options: ~w(combined read write)},
      %{
        id: "throughput",
        type: throughput,
        event: "select_throughput_type",
        color: "flaky",
        options: ~w(combined downloads uploads)
      }
    ]
  end

  defp transport_title("transfer", "combined"), do: dgettext("dashboard_cache", "Cache transfer")
  defp transport_title("transfer", "downloads"), do: dgettext("dashboard_cache", "Cache downloads")
  defp transport_title("transfer", "uploads"), do: dgettext("dashboard_cache", "Cache uploads")
  defp transport_title("latency", "combined"), do: dgettext("dashboard_cache", "Cache latency")
  defp transport_title("latency", "read"), do: dgettext("dashboard_cache", "Read latency")
  defp transport_title("latency", "write"), do: dgettext("dashboard_cache", "Write latency")
  defp transport_title("throughput", "combined"), do: dgettext("dashboard_cache", "Cache throughput")
  defp transport_title("throughput", "downloads"), do: dgettext("dashboard_cache", "Download throughput")
  defp transport_title("throughput", "uploads"), do: dgettext("dashboard_cache", "Upload throughput")

  defp transport_color(_color, type) when type in ~w(downloads read), do: "secondary"
  defp transport_color(_color, type) when type in ~w(uploads write), do: "p99"
  defp transport_color(color, _type), do: color

  defp transport_value(_widget, nil), do: value(nil)
  defp transport_value("transfer", bytes), do: ByteFormatter.format_bytes(bytes)
  defp transport_value("latency", duration), do: duration |> round() |> DateFormatter.format_duration_from_milliseconds()
  defp transport_value("throughput", bytes), do: ThroughputFormatter.format_throughput(bytes)

  defp transport_metric(analytics, widget, type), do: analytics.transport[String.to_existing_atom(widget)].metrics[type]
  defp transport_trend(analytics, widget, type), do: analytics.transport[String.to_existing_atom(widget)].trends[type]

  defp chart_available?(analytics, "hit_rate"), do: analytics.series != []

  defp chart_available?(analytics, widget),
    do: Enum.any?(analytics.transport[String.to_existing_atom(widget)].metrics, fn {_, metric} -> metric != nil end)

  defp analytics_series(analytics, "hit_rate"), do: analytics.series
  defp analytics_series(analytics, widget), do: analytics.transport[String.to_existing_atom(widget)].series
  defp chart_formatter("hit_rate"), do: "{value}%"
  defp chart_formatter("transfer"), do: "fn:formatBytes"
  defp chart_formatter("latency"), do: "fn:formatMilliseconds"
  defp chart_formatter("throughput"), do: "fn:formatMbps"

  defp chart_options(series, formatter) do
    dates = Enum.map(series, &to_string(&1.date))

    %{
      grid:
        if formatter == "{value}%" do
          %{width: "97%", left: "0.4%", height: "60%", top: "10%"}
        else
          %{width: "93%", left: "0.4%", right: "7%", height: "60%", top: "5%"}
        end,
      legend: %{
        show: true,
        left: "left",
        top: "bottom",
        orient: "horizontal",
        textStyle: %{
          color: "var:noora-surface-label-secondary",
          fontFamily: "monospace",
          fontSize: 10,
          fontWeight: 400,
          lineHeight: 12
        },
        icon:
          "path://M0 6C0 4.89543 0.895431 4 2 4H6C7.10457 4 8 4.895431 8 6C8 7.10457 7.10457 8 6 8H2C0.895431 8 0 7.10457 0 6Z",
        itemWidth: 8,
        itemHeight: 4
      },
      xAxis: %{
        boundaryGap: false,
        type: "category",
        data: dates,
        axisLabel: %{
          color: "var:noora-surface-label-secondary",
          formatter: "fn:toLocaleDate",
          customValues: [List.first(dates), List.last(dates)],
          padding: [10, 0, 0, 0]
        }
      },
      yAxis: %{
        splitNumber: if(formatter == "{value}%", do: 4, else: 5),
        splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
        axisLabel: %{color: "var:noora-surface-label-secondary", formatter: formatter}
      },
      tooltip: %{valueFormat: formatter}
    }
  end

  defp chart_series(analytics, "hit_rate") do
    series = analytics.series

    Enum.map(~w(avg p99 p90 p50), fn metric ->
      %{
        name: series_name(metric),
        type: "line",
        color: "var:noora-chart-#{percentile_color(metric)}",
        data: Enum.map(series, &[to_string(&1.date), selected_metric(&1, metric)]),
        smooth: 0.1,
        symbol: chart_symbol(series, &selected_metric(&1, metric)),
        connectNulls: false
      }
    end)
  end

  defp chart_series(analytics, widget) do
    series = analytics_series(analytics, widget)
    metric = Enum.find(transport_widgets("combined", "combined", "combined"), &(&1.id == widget))

    Enum.with_index(metric.options, fn type, index ->
      %{
        name: transport_title(widget, type),
        type: "line",
        color: "var:noora-chart-#{Enum.at([metric.color, "secondary", "p99"], index)}",
        data: Enum.map(series, &[to_string(&1.date), &1[type]]),
        smooth: 0.1,
        symbol: chart_symbol(series, & &1[type]),
        connectNulls: false
      }
    end)
  end

  defp chart_symbol(series, value_fn) do
    if length(series) == 1 or Enum.any?(series, &(value_fn.(&1) == nil)), do: "circle", else: "none"
  end

  defp recent_hit_rate_label(%{hit_rate: nil, bypasses: bypasses}) when bypasses > 0,
    do: dgettext("dashboard", "Not cached")

  defp recent_hit_rate_label(%{hit_rate: nil}), do: dgettext("dashboard_builds", "No recorded lookups")
  defp recent_hit_rate_label(%{hit_rate: rate}), do: value(rate)

  defp recent_builds_coverage(rows) do
    dngettext(
      "dashboard_cache",
      "Cache results recorded for %{measured} of %{total} recent build. Builds without recorded cache results are excluded from the hit rate.",
      "Cache results recorded for %{measured} of %{total} recent builds. Builds without recorded cache results are excluded from the hit rate.",
      length(rows),
      measured: format_number(Enum.count(rows, &(not is_nil(&1.cache.hit_rate)))),
      total: format_number(length(rows))
    )
  end

  defp recent_chart_data(rows, account, project) do
    rows
    |> Enum.reverse()
    |> Enum.map(fn row ->
      %{
        value: row.cache.hit_rate,
        date: recent_build_datetime(row.build),
        url: recent_build_path(row, account, project)
      }
    end)
  end

  defp recent_build_datetime(build), do: DateTime.from_naive!(build.inserted_at, "Etc/UTC")

  defp date_selection(socket, params, period_params) do
    if socket.assigns[:period_params] == period_params and socket.assigns[:period],
      do: %{preset: socket.assigns.preset, period: socket.assigns.period},
      else: DatePicker.date_picker_params(params, "analytics")
  end
end
