defmodule TuistWeb.XcodeCacheLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.Skeleton
  import TuistWeb.EmptyState
  import TuistWeb.PercentileDropdownWidget
  import TuistWeb.Runs.RanByBadge

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

    if socket.assigns.uploads_analytics.ok? do
      chart_data =
        analytics_chart_data(
          widget,
          socket.assigns.uploads_analytics.result,
          socket.assigns.downloads_analytics.result,
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

  defp assign_analytics(%{assigns: %{selected_project: project}} = socket, params) do
    %{preset: preset, period: {start_datetime, end_datetime} = period} =
      DatePicker.date_picker_params(params, "analytics")

    opts = [
      project_id: project.id,
      start_datetime: start_datetime,
      end_datetime: end_datetime
    ]

    uri = URI.new!("?" <> URI.encode_query(params))

    analytics_selected_widget = params["analytics-selected-widget"] || "cache_hit_rate"

    socket
    |> assign(:analytics_preset, preset)
    |> assign(:analytics_period, period)
    |> assign(:analytics_trend_label, analytics_trend_label(preset))
    |> assign(:analytics_selected_widget, analytics_selected_widget)
    |> assign(:selected_hit_rate_type, params["hit-rate-type"] || "avg")
    |> assign(:uri, uri)
    |> assign_async([:uploads_analytics, :downloads_analytics, :hit_rate_analytics, :analytics_chart_data], fn ->
      uploads_analytics = Analytics.cas_uploads_analytics(project.id, opts)
      downloads_analytics = Analytics.cas_downloads_analytics(project.id, opts)
      hit_rate_analytics = Analytics.build_cache_hit_rate_analytics(project.id, opts)

      {:ok,
       %{
         uploads_analytics: uploads_analytics,
         downloads_analytics: downloads_analytics,
         hit_rate_analytics: hit_rate_analytics,
         analytics_chart_data:
           analytics_chart_data(
             analytics_selected_widget,
             uploads_analytics,
             downloads_analytics,
             hit_rate_analytics
           )
       }}
    end)
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

  defp analytics_chart_data("cache_uploads", uploads_analytics, _downloads_analytics, _hit_rate_analytics) do
    %{
      dates: uploads_analytics.dates,
      values: uploads_analytics.values,
      name: dgettext("dashboard_cache", "Cache uploads"),
      value_formatter: "fn:formatBytes"
    }
  end

  defp analytics_chart_data("cache_downloads", _uploads_analytics, downloads_analytics, _hit_rate_analytics) do
    %{
      dates: downloads_analytics.dates,
      values: downloads_analytics.values,
      name: dgettext("dashboard_cache", "Cache downloads"),
      value_formatter: "fn:formatBytes"
    }
  end

  defp analytics_chart_data(_cache_hit_rate, _uploads_analytics, _downloads_analytics, hit_rate_analytics) do
    %{
      dates: hit_rate_analytics.dates,
      values: hit_rate_analytics.values,
      name: dgettext("dashboard_cache", "Cache hit rate"),
      value_formatter: "{value}%"
    }
  end

  defp analytics_trend_label("last-24-hours"), do: dgettext("dashboard_cache", "since yesterday")
  defp analytics_trend_label("last-7-days"), do: dgettext("dashboard_cache", "since last week")
  defp analytics_trend_label("last-12-months"), do: dgettext("dashboard_cache", "since last year")
  defp analytics_trend_label("custom"), do: dgettext("dashboard_cache", "since last period")
  defp analytics_trend_label(_), do: dgettext("dashboard_cache", "since last month")

  defp assign_recent_builds(%{assigns: %{selected_project: project}} = socket, _params) do
    options = %{
      filters: [
        %{field: :project_id, op: :==, value: project.id},
        %{field: :cacheable_tasks_count, op: :>, value: 0}
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
end
