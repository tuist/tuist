defmodule TuistWeb.GradleInsightsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.EmptyState
  import TuistWeb.PercentileDropdownWidget

  alias Tuist.Gradle
  alias Tuist.Gradle.Analytics
  alias Tuist.Utilities.ByteFormatter
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    slug = "#{account.name}/#{project.name}"

    socket =
      socket
      |> assign(:head_title, "#{dgettext("dashboard_gradle", "Gradle Insights")} · #{slug} · Tuist")
      |> assign(OpenGraph.og_image_assigns("gradle-insights"))

    if connected?(socket) do
      Tuist.PubSub.subscribe("#{account.name}/#{project.name}")
    end

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    {
      :noreply,
      socket
      |> assign(:current_params, params)
      |> assign_analytics(params)
      |> assign_recent_builds(params)
    }
  end

  def handle_event(
        "select_widget",
        %{"widget" => widget},
        %{assigns: %{selected_account: selected_account, selected_project: selected_project, uri: uri}} = socket
      ) do
    socket =
      push_patch(
        socket,
        to:
          "/#{selected_account.name}/#{selected_project.name}/gradle-insights?#{Query.put(uri.query, "analytics-selected-widget", widget)}",
        replace: true
      )

    {:noreply, socket}
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
          "/#{selected_account.name}/#{selected_project.name}/gradle-insights?#{Query.put(uri.query, "hit-rate-type", type)}",
        replace: true
      )

    {:noreply, socket}
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

    {:noreply,
     push_patch(socket, to: "/#{selected_account.name}/#{selected_project.name}/gradle-insights?#{query_params}")}
  end

  def handle_info({:gradle_build_created, _build}, socket) do
    if Query.has_pagination_params?(socket.assigns.uri.query) do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign_analytics(socket.assigns.current_params)
       |> assign_recent_builds(socket.assigns.current_params)}
    end
  end

  def handle_info(_event, socket) do
    {:noreply, socket}
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

    [hit_rate_analytics, hit_rate_p99, hit_rate_p90, hit_rate_p50, task_breakdown, cache_events] =
      Analytics.combined_gradle_analytics(project.id, opts)

    analytics_selected_widget = params["analytics-selected-widget"] || "cache_hit_rate"

    analytics_chart_data =
      case analytics_selected_widget do
        "cache_uploads" ->
          %{
            dates: cache_events.uploads.dates,
            values: cache_events.uploads.values,
            name: dgettext("dashboard_gradle", "Cache uploads"),
            value_formatter: "fn:formatBytes"
          }

        "cache_downloads" ->
          %{
            dates: cache_events.downloads.dates,
            values: cache_events.downloads.values,
            name: dgettext("dashboard_gradle", "Cache downloads"),
            value_formatter: "fn:formatBytes"
          }

        "cache_hit_rate" ->
          %{
            dates: hit_rate_analytics.dates,
            values: hit_rate_analytics.values,
            name: dgettext("dashboard_gradle", "Cache hit rate"),
            value_formatter: "{value}%"
          }
      end

    socket
    |> assign(:analytics_preset, preset)
    |> assign(:analytics_period, period)
    |> assign(:analytics_trend_label, analytics_trend_label(preset))
    |> assign(:analytics_selected_widget, analytics_selected_widget)
    |> assign(:hit_rate_analytics, hit_rate_analytics)
    |> assign(:hit_rate_p99, hit_rate_p99)
    |> assign(:hit_rate_p90, hit_rate_p90)
    |> assign(:hit_rate_p50, hit_rate_p50)
    |> assign(:task_breakdown, task_breakdown)
    |> assign(:cache_events, cache_events)
    |> assign(:selected_hit_rate_type, params["hit-rate-type"] || "avg")
    |> assign(:analytics_chart_data, analytics_chart_data)
    |> assign(:uri, uri)
  end

  defp analytics_trend_label("last-24-hours"), do: dgettext("dashboard_gradle", "since yesterday")
  defp analytics_trend_label("last-7-days"), do: dgettext("dashboard_gradle", "since last week")
  defp analytics_trend_label("last-12-months"), do: dgettext("dashboard_gradle", "since last year")
  defp analytics_trend_label("custom"), do: dgettext("dashboard_gradle", "since last period")
  defp analytics_trend_label(_), do: dgettext("dashboard_gradle", "since last month")

  defp assign_recent_builds(%{assigns: %{selected_project: project}} = socket, _params) do
    builds = Gradle.list_builds(project.id, limit: 40)

    recent_builds_chart_data =
      builds
      |> Enum.reverse()
      |> Enum.map(fn build ->
        hit_rate = cache_hit_rate(build)

        %{
          value: hit_rate,
          date: build.inserted_at
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
    from_cache = build.tasks_from_cache_count || 0
    executed = build.tasks_executed_count || 0
    total = from_cache + executed

    if total == 0 do
      0.0
    else
      Float.round(from_cache / total * 100.0, 1)
    end
  end

  def avoidance_rate(build) do
    from_cache = build.tasks_from_cache_count || 0
    up_to_date = build.tasks_up_to_date_count || 0
    executed = build.tasks_executed_count || 0
    failed = build.tasks_failed_count || 0
    skipped = build.tasks_skipped_count || 0
    no_source = build.tasks_no_source_count || 0
    total = from_cache + up_to_date + executed + failed + skipped + no_source

    if total == 0 do
      0.0
    else
      Float.round((from_cache + up_to_date) / total * 100.0, 1)
    end
  end
end
