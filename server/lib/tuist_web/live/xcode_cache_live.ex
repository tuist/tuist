defmodule TuistWeb.XcodeCacheLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.ChartTypeToggle
  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.ScatterChart
  import TuistWeb.Components.Skeleton
  import TuistWeb.EmptyState
  import TuistWeb.PercentileDropdownWidget
  import TuistWeb.Runs.RanByBadge
  import TuistWeb.SplitDropdownWidget

  alias Phoenix.LiveView.AsyncResult
  alias Tuist.Builds
  alias Tuist.Builds.Analytics
  alias Tuist.Builds.Build
  alias Tuist.Utilities.ByteFormatter
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    slug = "#{account.name}/#{project.name}"

    socket =
      socket
      |> assign(:head_title, "#{dgettext("dashboard_cache", "Xcode Cache")} · #{slug} · Tuist")
      |> assign(OpenGraph.og_image_assigns("xcode-cache"))

    {:ok, socket}
  end

  def handle_params(_params, uri, %{assigns: %{selected_project: project}} = socket) do
    params = Query.query_params(uri)

    {has_builds_check, _} =
      Builds.list_build_runs(%{
        filters: [
          %{field: :project_id, op: :==, value: project.id},
          %{field: :cacheable_tasks_count, op: :>, value: 0}
        ],
        first: 1,
        order_by: [:inserted_at],
        order_directions: [:desc]
      })

    has_builds? = not Enum.empty?(has_builds_check)

    {
      :noreply,
      socket
      |> assign(:has_builds?, has_builds?)
      |> assign(:current_params, params)
      |> assign_analytics(params)
      |> assign_recent_builds(params)
    }
  end

  def handle_event("select_widget", %{"widget" => widget}, socket) do
    query = Query.put(socket.assigns.uri.query, "analytics-selected-widget", widget)
    uri = URI.new!("?" <> query)

    socket =
      socket
      |> assign(:analytics_selected_widget, widget)
      |> assign(:uri, uri)
      |> push_event("replace-url", %{url: "?" <> query})

    if socket.assigns.transfer_analytics.ok? do
      chart_data =
        analytics_chart_data(
          widget,
          socket.assigns.transfer_analytics.result,
          socket.assigns.latency_analytics.result,
          socket.assigns.throughput_analytics.result,
          socket.assigns.hit_rate_analytics.result
        )

      {:noreply, assign(socket, :analytics_chart_data, %{socket.assigns.analytics_chart_data | result: chart_data})}
    else
      {:noreply, socket}
    end
  end

  def handle_event(
        "select_hit_rate_type",
        %{"type" => type},
        %{assigns: %{selected_account: selected_account, selected_project: selected_project, uri: uri}} = socket
      ) do
    socket =
      push_patch(
        socket,
        to:
          "/#{selected_account.name}/#{selected_project.name}/xcode-cache?#{Query.put(uri.query, "hit-rate-type", type)}",
        replace: true
      )

    {:noreply, socket}
  end

  def handle_event("select_transfer_type", %{"type" => type}, socket) do
    {:noreply, replace_split_query_param(socket, "transfer-type", type)}
  end

  def handle_event("select_latency_type", %{"type" => type}, socket) do
    {:noreply, replace_split_query_param(socket, "latency-type", type)}
  end

  def handle_event("select_throughput_type", %{"type" => type}, socket) do
    {:noreply, replace_split_query_param(socket, "throughput-type", type)}
  end

  def handle_event("select_cache_hit_rate_chart_type", %{"type" => type}, socket) do
    query = Query.put(socket.assigns.uri.query, "cache-hit-rate-chart-type", type)
    uri = URI.new!("?" <> query)
    socket = assign(socket, cache_hit_rate_chart_type: type, uri: uri)
    opts = analytics_opts(socket.assigns)

    {:noreply,
     socket
     |> push_event("replace-url", %{url: "?" <> query})
     |> assign_cache_hit_rate_chart(type, scatter_group_by_atom(socket.assigns.cache_hit_rate_scatter_group_by), opts)}
  end

  def handle_event(
        "analytics_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        %{assigns: %{selected_account: selected_account, selected_project: selected_project}} = socket
      ) do
    query_params =
      if preset == "custom" do
        socket.assigns.uri.query
        |> Query.put("analytics-date-range", "custom")
        |> Query.put("analytics-start-date", start_date)
        |> Query.put("analytics-end-date", end_date)
      else
        Query.put(socket.assigns.uri.query, "analytics-date-range", preset)
      end

    {:noreply, push_patch(socket, to: "/#{selected_account.name}/#{selected_project.name}/xcode-cache?#{query_params}")}
  end

  def handle_info(_event, socket) do
    {:noreply, socket}
  end

  defp replace_split_query_param(
         %{assigns: %{selected_account: selected_account, selected_project: selected_project, uri: uri}} = socket,
         key,
         value
       ) do
    push_patch(
      socket,
      to: "/#{selected_account.name}/#{selected_project.name}/xcode-cache?#{Query.put(uri.query, key, value)}",
      replace: true
    )
  end

  defp assign_analytics(%{assigns: %{selected_project: project}} = socket, params) do
    %{preset: preset, period: {start_datetime, end_datetime} = period} =
      DatePicker.date_picker_params(params, "analytics")

    opts = [
      project_id: project.id,
      start_datetime: start_datetime,
      end_datetime: end_datetime
    ]

    uri = URI.new!("?" <> URI.encode_query(params))

    analytics_selected_widget = Map.get(params, "analytics-selected-widget", "cache_hit_rate")
    cache_hit_rate_chart_type = Map.get(params, "cache-hit-rate-chart-type", "line")
    cache_hit_rate_scatter_group_by = Map.get(params, "cache-hit-rate-scatter-group-by", "scheme")
    scatter_group_by_atom = scatter_group_by_atom(cache_hit_rate_scatter_group_by)

    socket
    |> assign(:analytics_preset, preset)
    |> assign(:analytics_period, period)
    |> assign(:analytics_trend_label, analytics_trend_label(preset))
    |> assign(:analytics_selected_widget, analytics_selected_widget)
    |> assign(:selected_hit_rate_type, Map.get(params, "hit-rate-type", "avg"))
    |> assign(:selected_transfer_type, Map.get(params, "transfer-type", "combined"))
    |> assign(:selected_latency_type, Map.get(params, "latency-type", "combined"))
    |> assign(:selected_throughput_type, Map.get(params, "throughput-type", "combined"))
    |> assign(:cache_hit_rate_chart_type, cache_hit_rate_chart_type)
    |> assign(:cache_hit_rate_scatter_group_by, cache_hit_rate_scatter_group_by)
    |> assign(:uri, uri)
    |> assign_async(
      [:transfer_analytics, :latency_analytics, :throughput_analytics, :hit_rate_analytics, :analytics_chart_data],
      fn ->
        transfer_analytics = Analytics.cas_transfer_analytics(project.id, opts)
        latency_analytics = Analytics.cas_latency_analytics(project.id, opts)
        throughput_analytics = Analytics.cas_throughput_analytics(project.id, opts)
        hit_rate_analytics = Analytics.build_cache_hit_rate_analytics(project.id, opts)

        {:ok,
         %{
           transfer_analytics: transfer_analytics,
           latency_analytics: latency_analytics,
           throughput_analytics: throughput_analytics,
           hit_rate_analytics: hit_rate_analytics,
           analytics_chart_data:
             analytics_chart_data(
               analytics_selected_widget,
               transfer_analytics,
               latency_analytics,
               throughput_analytics,
               hit_rate_analytics
             )
         }}
      end
    )
    |> assign_cache_hit_rate_chart(cache_hit_rate_chart_type, scatter_group_by_atom, opts)
    |> assign_async(:hit_rate_p99, fn ->
      {:ok, %{hit_rate_p99: Analytics.build_cache_hit_rate_percentile(project.id, 0.99, opts)}}
    end)
    |> assign_async(:hit_rate_p90, fn ->
      {:ok, %{hit_rate_p90: Analytics.build_cache_hit_rate_percentile(project.id, 0.9, opts)}}
    end)
    |> assign_async(:hit_rate_p50, fn ->
      {:ok, %{hit_rate_p50: Analytics.build_cache_hit_rate_percentile(project.id, 0.5, opts)}}
    end)
  end

  defp analytics_chart_data("cache_transfer", transfer, _latency, _throughput, _hit_rate) do
    %{
      dates: transfer.dates,
      value_formatter: "fn:formatBytes",
      series: [
        %{
          name: dgettext("dashboard_cache", "Cache transfer"),
          color: "var:noora-chart-p50",
          values: transfer.values
        },
        %{
          name: dgettext("dashboard_cache", "Cache downloads"),
          color: "var:noora-chart-secondary",
          values: transfer.downloads.values
        },
        %{
          name: dgettext("dashboard_cache", "Cache uploads"),
          color: "var:noora-chart-p99",
          values: transfer.uploads.values
        }
      ]
    }
  end

  defp analytics_chart_data("cache_latency", _transfer, latency, _throughput, _hit_rate) do
    %{
      dates: latency.dates,
      value_formatter: "fn:formatMilliseconds",
      series: [
        %{
          name: dgettext("dashboard_cache", "Cache latency"),
          color: "var:noora-chart-p90",
          values: latency.values
        },
        %{
          name: dgettext("dashboard_cache", "Read latency"),
          color: "var:noora-chart-secondary",
          values: latency.downloads.values
        },
        %{
          name: dgettext("dashboard_cache", "Write latency"),
          color: "var:noora-chart-p99",
          values: latency.uploads.values
        }
      ]
    }
  end

  defp analytics_chart_data("cache_throughput", _transfer, _latency, throughput, _hit_rate) do
    %{
      dates: throughput.dates,
      value_formatter: "fn:formatMbps",
      series: [
        %{
          name: dgettext("dashboard_cache", "Cache throughput"),
          color: "var:noora-chart-flaky",
          values: throughput.values
        },
        %{
          name: dgettext("dashboard_cache", "Download throughput"),
          color: "var:noora-chart-secondary",
          values: throughput.downloads.values
        },
        %{
          name: dgettext("dashboard_cache", "Upload throughput"),
          color: "var:noora-chart-p99",
          values: throughput.uploads.values
        }
      ]
    }
  end

  defp analytics_chart_data(_cache_hit_rate, _transfer, _latency, _throughput, hit_rate) do
    %{
      dates: hit_rate.dates,
      value_formatter: "{value}%",
      series: [
        %{
          name: dgettext("dashboard_cache", "Cache hit rate"),
          color: "var:noora-chart-primary",
          values: hit_rate.values
        }
      ]
    }
  end

  def transfer_value(result, "downloads"), do: result.downloads.total
  def transfer_value(result, "uploads"), do: result.uploads.total
  def transfer_value(result, _combined), do: result.total

  def latency_value(result, "read"), do: result.downloads.total
  def latency_value(result, "write"), do: result.uploads.total
  def latency_value(result, _combined), do: result.total

  def throughput_value(result, "downloads"), do: result.downloads.total
  def throughput_value(result, "uploads"), do: result.uploads.total
  def throughput_value(result, _combined), do: result.total

  def split_legend_color(selected, combined_color \\ "primary")
  def split_legend_color("downloads", _combined_color), do: "secondary"
  def split_legend_color("uploads", _combined_color), do: "p99"
  def split_legend_color("read", _combined_color), do: "secondary"
  def split_legend_color("write", _combined_color), do: "p99"
  def split_legend_color(_combined, combined_color), do: combined_color

  defp analytics_trend_label("last-24-hours"), do: dgettext("dashboard_cache", "since yesterday")
  defp analytics_trend_label("last-7-days"), do: dgettext("dashboard_cache", "since last week")
  defp analytics_trend_label("last-12-months"), do: dgettext("dashboard_cache", "since last year")
  defp analytics_trend_label("custom"), do: dgettext("dashboard_cache", "since last period")
  defp analytics_trend_label(_), do: dgettext("dashboard_cache", "since last month")

  defp assign_recent_builds(%{assigns: %{selected_project: project}} = socket, _params) do
    {start_datetime, end_datetime} = socket.assigns.analytics_period

    options = %{
      filters: [
        %{field: :project_id, op: :==, value: project.id},
        %{field: :cacheable_tasks_count, op: :>, value: 0},
        %{field: :inserted_at, op: :>=, value: start_datetime},
        %{field: :inserted_at, op: :<, value: DateTime.add(end_datetime, 1, :second)}
      ],
      order_by: [:inserted_at],
      order_directions: [:desc],
      first: 40,
      for: Build
    }

    {builds, _} = Builds.list_build_runs(options, preload: [:ran_by_account])

    recent_builds_chart_data =
      builds
      |> Enum.reverse()
      |> Enum.map(fn build ->
        hit_rate = cache_hit_rate(build)

        %{
          value: hit_rate,
          date: build.inserted_at,
          url: ~p"/#{project.account.name}/#{project.name}/builds/build-runs/#{build.id}"
        }
      end)

    avg_recent_hit_rate =
      if Enum.empty?(recent_builds_chart_data) do
        0.0
      else
        total =
          recent_builds_chart_data
          |> Enum.map(& &1.value)
          |> Enum.sum()

        Float.round(total / length(recent_builds_chart_data), 1)
      end

    socket
    |> assign(:builds, builds)
    |> assign(:recent_builds_chart_data, recent_builds_chart_data)
    |> assign(:avg_recent_hit_rate, avg_recent_hit_rate)
  end

  def cache_hit_rate(build) do
    total = build.cacheable_tasks_count || 0
    local_hits = build.cacheable_task_local_hits_count || 0
    remote_hits = build.cacheable_task_remote_hits_count || 0

    if total == 0 do
      0.0
    else
      Float.round((local_hits + remote_hits) / total * 100.0, 1)
    end
  end

  defp with_tooltip_extra(scatter_data, group_by) do
    Map.update!(scatter_data, :series, fn series ->
      Enum.map(series, fn s ->
        %{
          name: scatter_name_label(s.name, group_by),
          data:
            Enum.map(s.data, fn point ->
              point
              |> Map.take([:value, :id])
              |> Map.put(:tooltipExtra, tooltip_extra(point.meta))
            end)
        }
      end)
    end)
  end

  defp scatter_name_label(value, :environment), do: environment_label(value)
  defp scatter_name_label(value, _), do: scheme_label(value)

  defp tooltip_extra(meta) do
    [
      %{label: dgettext("dashboard_cache", "Scheme"), value: scheme_label(meta.scheme)},
      %{label: dgettext("dashboard_cache", "Status"), value: status_label(meta.status)},
      %{label: dgettext("dashboard_cache", "Environment"), value: environment_label(meta.is_ci)}
    ]
  end

  defp environment_label(true), do: dgettext("dashboard_cache", "CI")
  defp environment_label(false), do: dgettext("dashboard_cache", "Local")

  defp scheme_label(value) when value in ["", nil], do: dgettext("dashboard_cache", "Unknown")
  defp scheme_label(value), do: value

  defp status_label("success"), do: dgettext("dashboard_cache", "Passed")
  defp status_label("failure"), do: dgettext("dashboard_cache", "Failed")
  defp status_label(status), do: String.capitalize(status)

  defp assign_cache_hit_rate_chart(socket, "scatter", group_by, opts) do
    project_id = socket.assigns.selected_project.id

    assign_async(socket, :cache_hit_rate_chart, fn ->
      data =
        project_id
        |> Analytics.build_cache_hit_rate_scatter_data(Keyword.put(opts, :group_by, group_by))
        |> with_tooltip_extra(group_by)

      {:ok, %{cache_hit_rate_chart: {:scatter, data}}}
    end)
  end

  defp assign_cache_hit_rate_chart(socket, _line, _group_by, _opts) do
    assign(socket, :cache_hit_rate_chart, AsyncResult.ok(:line))
  end

  defp analytics_opts(%{selected_project: project, analytics_period: {start_datetime, end_datetime}}) do
    [project_id: project.id, start_datetime: start_datetime, end_datetime: end_datetime]
  end

  defp scatter_group_by_atom("environment"), do: :environment
  defp scatter_group_by_atom(_), do: :scheme
end
