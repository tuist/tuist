defmodule TuistWeb.GradleCacheLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.Skeleton
  import TuistWeb.EmptyState
  import TuistWeb.PercentileDropdownWidget
  import TuistWeb.Runs.RanByBadge

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
    %{preset: preset, period: {start_datetime, end_datetime} = period} =
      DatePicker.date_picker_params(params, "analytics")

    analytics_environment = params["analytics-environment"] || "any"

    opts =
      then(
        [
          project_id: project.id,
          start_datetime: start_datetime,
          end_datetime: end_datetime
        ],
        fn opts ->
          case analytics_environment do
            "ci" -> Keyword.put(opts, :is_ci, true)
            "local" -> Keyword.put(opts, :is_ci, false)
            _ -> opts
          end
        end
      )

    uri = URI.new!("?" <> URI.encode_query(params))

    analytics_selected_widget = params["analytics-selected-widget"] || "cache_hit_rate"

    socket
    |> assign(:analytics_preset, preset)
    |> assign(:analytics_period, period)
    |> assign(:analytics_trend_label, analytics_trend_label(preset))
    |> assign(:analytics_selected_widget, analytics_selected_widget)
    |> assign(:selected_hit_rate_type, params["hit-rate-type"] || "avg")
    |> assign(:analytics_environment, analytics_environment)
    |> assign(:analytics_environment_label, environment_label(analytics_environment))
    |> assign(:uri, uri)
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

  defp analytics_trend_label("last-24-hours"), do: dgettext("dashboard_gradle", "since yesterday")
  defp analytics_trend_label("last-7-days"), do: dgettext("dashboard_gradle", "since last week")
  defp analytics_trend_label("last-12-months"), do: dgettext("dashboard_gradle", "since last year")
  defp analytics_trend_label("custom"), do: dgettext("dashboard_gradle", "since last period")
  defp analytics_trend_label(_), do: dgettext("dashboard_gradle", "since last month")

  defp assign_recent_builds(%{assigns: %{selected_project: project, selected_account: account}} = socket, _params) do
    {builds, _meta} = Gradle.list_builds(project.id, %{page_size: @recent_builds_page_size})
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
end
