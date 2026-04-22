defmodule TuistWeb.GradleCacheLive do
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

  alias Phoenix.LiveView.AsyncResult
  alias Tuist.Gradle
  alias Tuist.Gradle.Analytics
  alias Tuist.Repo
  alias Tuist.Utilities.ByteFormatter
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  @recent_builds_page_size 40

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    slug = "#{account.name}/#{project.name}"

    socket =
      socket
      |> assign(:head_title, "#{dgettext("dashboard_gradle", "Gradle Cache")} · #{slug} · Tuist")
      |> assign(OpenGraph.og_image_assigns("gradle-cache"))

    {:ok, socket}
  end

  def handle_params(_params, uri, socket) do
    params = Query.query_params(uri)

    {
      :noreply,
      socket
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

    if socket.assigns.hit_rate_analytics.ok? do
      chart_data =
        analytics_chart_data(
          widget,
          socket.assigns.hit_rate_analytics.result,
          socket.assigns.cache_events.result
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
          "/#{selected_account.name}/#{selected_project.name}/gradle-cache?#{Query.put(uri.query, "hit-rate-type", type)}",
        replace: true
      )

    {:noreply, socket}
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

    {:noreply, push_patch(socket, to: "/#{selected_account.name}/#{selected_project.name}/gradle-cache?#{query_params}")}
  end

  def handle_info(_event, socket) do
    {:noreply, socket}
  end

  defp assign_analytics(%{assigns: %{selected_project: project}} = socket, params) do
    %{preset: preset, period: period} = DatePicker.date_picker_params(params, "analytics")
    analytics_environment = params["analytics-environment"] || "any"
    analytics_selected_widget = params["analytics-selected-widget"] || "cache_hit_rate"
    cache_hit_rate_chart_type = params["cache-hit-rate-chart-type"] || "line"
    cache_hit_rate_scatter_group_by = params["cache-hit-rate-scatter-group-by"] || "environment"
    uri = URI.new!("?" <> URI.encode_query(params))

    socket =
      socket
      |> assign(:analytics_preset, preset)
      |> assign(:analytics_period, period)
      |> assign(:analytics_trend_label, analytics_trend_label(preset))
      |> assign(:analytics_selected_widget, analytics_selected_widget)
      |> assign(:selected_hit_rate_type, params["hit-rate-type"] || "avg")
      |> assign(:cache_hit_rate_chart_type, cache_hit_rate_chart_type)
      |> assign(:cache_hit_rate_scatter_group_by, cache_hit_rate_scatter_group_by)
      |> assign(:analytics_environment, analytics_environment)
      |> assign(:analytics_environment_label, environment_label(analytics_environment))
      |> assign(:uri, uri)

    opts = analytics_opts(socket.assigns)
    scatter_group_by_atom = scatter_group_by_atom(cache_hit_rate_scatter_group_by)

    socket
    |> assign_async([:hit_rate_analytics, :cache_events, :analytics_chart_data], fn ->
      hit_rate_analytics = Analytics.cache_hit_rate_analytics(project.id, opts)
      cache_events = Analytics.cache_event_analytics(project.id, opts)

      {:ok,
       %{
         hit_rate_analytics: hit_rate_analytics,
         cache_events: cache_events,
         analytics_chart_data:
           analytics_chart_data(
             analytics_selected_widget,
             hit_rate_analytics,
             cache_events
           )
       }}
    end)
    |> assign_cache_hit_rate_chart(cache_hit_rate_chart_type, scatter_group_by_atom, opts)
    |> assign_async(:hit_rate_p99, fn ->
      {:ok, %{hit_rate_p99: Analytics.cache_hit_rate_percentile(project.id, 0.99, opts)}}
    end)
    |> assign_async(:hit_rate_p90, fn ->
      {:ok, %{hit_rate_p90: Analytics.cache_hit_rate_percentile(project.id, 0.9, opts)}}
    end)
    |> assign_async(:hit_rate_p50, fn ->
      {:ok, %{hit_rate_p50: Analytics.cache_hit_rate_percentile(project.id, 0.5, opts)}}
    end)
  end

  defp analytics_chart_data("cache_uploads", _hit_rate_analytics, cache_events) do
    %{
      dates: cache_events.uploads.dates,
      values: cache_events.uploads.values,
      name: dgettext("dashboard_gradle", "Cache uploads"),
      value_formatter: "fn:formatBytes"
    }
  end

  defp analytics_chart_data("cache_downloads", _hit_rate_analytics, cache_events) do
    %{
      dates: cache_events.downloads.dates,
      values: cache_events.downloads.values,
      name: dgettext("dashboard_gradle", "Cache downloads"),
      value_formatter: "fn:formatBytes"
    }
  end

  defp analytics_chart_data(_cache_hit_rate, hit_rate_analytics, _cache_events) do
    %{
      dates: hit_rate_analytics.dates,
      values: hit_rate_analytics.values,
      name: dgettext("dashboard_gradle", "Cache hit rate"),
      value_formatter: "{value}%"
    }
  end

  defp environment_label("any"), do: dgettext("dashboard_gradle", "Any")
  defp environment_label("local"), do: dgettext("dashboard_gradle", "Local")
  defp environment_label("ci"), do: dgettext("dashboard_gradle", "CI")
  defp environment_label(true), do: dgettext("dashboard_gradle", "CI")
  defp environment_label(false), do: dgettext("dashboard_gradle", "Local")

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

  defp scatter_name_label(value, :project), do: project_label(value)
  defp scatter_name_label(value, _), do: environment_label(value)

  defp tooltip_extra(meta) do
    [
      %{label: dgettext("dashboard_gradle", "Project"), value: project_label(meta.root_project_name)},
      %{label: dgettext("dashboard_gradle", "Environment"), value: environment_label(meta.is_ci)}
    ]
  end

  defp project_label(value) when value in ["", nil], do: dgettext("dashboard_gradle", "Unknown")
  defp project_label(value), do: value

  defp analytics_trend_label("last-24-hours"), do: dgettext("dashboard_gradle", "since yesterday")
  defp analytics_trend_label("last-7-days"), do: dgettext("dashboard_gradle", "since last week")
  defp analytics_trend_label("last-12-months"), do: dgettext("dashboard_gradle", "since last year")
  defp analytics_trend_label("custom"), do: dgettext("dashboard_gradle", "since last period")
  defp analytics_trend_label(_), do: dgettext("dashboard_gradle", "since last month")

  defp assign_recent_builds(%{assigns: %{selected_project: project, selected_account: account}} = socket, _params) do
    {start_datetime, end_datetime} = socket.assigns.analytics_period
    analytics_environment = socket.assigns.analytics_environment

    filters =
      [
        %{field: :inserted_at, op: :>=, value: start_datetime},
        %{field: :inserted_at, op: :<=, value: end_datetime}
      ] ++
        case analytics_environment do
          "ci" -> [%{field: :is_ci, op: :==, value: true}]
          "local" -> [%{field: :is_ci, op: :==, value: false}]
          _ -> []
        end

    {builds, _meta} = Gradle.list_builds(project.id, %{page_size: @recent_builds_page_size, filters: filters})
    builds = Repo.preload(builds, :built_by_account)

    recent_builds_chart_data =
      builds
      |> Enum.reverse()
      |> Enum.map(fn build ->
        hit_rate = Gradle.cache_hit_rate(build)

        %{
          value: hit_rate,
          date: build.inserted_at,
          url: ~p"/#{account.name}/#{project.name}/builds/build-runs/#{build.id}"
        }
      end)

    avg_recent_hit_rate =
      if Enum.empty?(recent_builds_chart_data) do
        0.0
      else
        total =
          recent_builds_chart_data
          |> Enum.map(fn %{value: v} -> v || 0.0 end)
          |> Enum.sum()

        Float.round(total / length(recent_builds_chart_data), 1)
      end

    socket
    |> assign(:builds, builds)
    |> assign(:recent_builds_chart_data, recent_builds_chart_data)
    |> assign(:avg_recent_hit_rate, avg_recent_hit_rate)
  end

  defp assign_cache_hit_rate_chart(socket, "scatter", group_by, opts) do
    project_id = socket.assigns.selected_project.id

    assign_async(socket, :cache_hit_rate_chart, fn ->
      data =
        project_id
        |> Analytics.cache_hit_rate_scatter_data(Keyword.put(opts, :group_by, group_by))
        |> with_tooltip_extra(group_by)

      {:ok, %{cache_hit_rate_chart: {:scatter, data}}}
    end)
  end

  defp assign_cache_hit_rate_chart(socket, _line, _group_by, _opts) do
    assign(socket, :cache_hit_rate_chart, AsyncResult.ok(:line))
  end

  defp analytics_opts(%{
         selected_project: project,
         analytics_period: {start_datetime, end_datetime},
         analytics_environment: env
       }) do
    opts = [project_id: project.id, start_datetime: start_datetime, end_datetime: end_datetime]

    case env do
      "ci" -> Keyword.put(opts, :is_ci, true)
      "local" -> Keyword.put(opts, :is_ci, false)
      _ -> opts
    end
  end

  defp scatter_group_by_atom("project"), do: :project
  defp scatter_group_by_atom(_), do: :environment
end
