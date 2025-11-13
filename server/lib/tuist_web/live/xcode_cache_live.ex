defmodule TuistWeb.XcodeCacheLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Ecto.Query
  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.PercentileDropdownWidget
  import TuistWeb.Runs.RanByBadge

  alias Tuist.Runs.Analytics
  alias Tuist.Runs.Build
  alias Tuist.Utilities.ByteFormatter
  alias TuistWeb.Utilities.Query

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    slug = "#{account.name}/#{project.name}"

    socket = assign(socket, :head_title, "#{gettext("Xcode Cache")} · #{slug} · Tuist")

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
          "/#{selected_account.name}/#{selected_project.name}/xcode-cache?#{Query.put(uri.query, "analytics_selected_widget", widget)}",
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
          "/#{selected_account.name}/#{selected_project.name}/xcode-cache?#{Query.put(uri.query, "hit-rate-type", type)}",
        replace: true
      )

    {:noreply, socket}
  end

  def handle_info({:build_created, _build}, socket) do
    # Only update when pagination is inactive
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
    date_range = date_range(params)

    opts = [
      project_id: project.id,
      start_date: start_date(date_range)
    ]

    uri = URI.new!("?" <> URI.encode_query(params))

    [uploads_analytics, downloads_analytics, hit_rate_analytics, hit_rate_p99, hit_rate_p90, hit_rate_p50] =
      Analytics.combined_cache_analytics(project.id, opts)

    analytics_selected_widget = analytics_selected_widget(params)

    analytics_chart_data =
      case analytics_selected_widget do
        "cache_uploads" ->
          %{
            dates: uploads_analytics.dates,
            values: uploads_analytics.values,
            name: gettext("Cache uploads"),
            value_formatter: "fn:formatBytes"
          }

        "cache_downloads" ->
          %{
            dates: downloads_analytics.dates,
            values: downloads_analytics.values,
            name: gettext("Cache downloads"),
            value_formatter: "fn:formatBytes"
          }

        "cache_hit_rate" ->
          %{
            dates: hit_rate_analytics.dates,
            values: hit_rate_analytics.values,
            name: gettext("Cache hit rate"),
            value_formatter: "{value}%"
          }
      end

    socket
    |> assign(
      :analytics_date_range,
      date_range
    )
    |> assign(
      :analytics_trend_label,
      analytics_trend_label(date_range)
    )
    |> assign(
      :analytics_selected_widget,
      analytics_selected_widget
    )
    |> assign(
      :uploads_analytics,
      uploads_analytics
    )
    |> assign(
      :downloads_analytics,
      downloads_analytics
    )
    |> assign(
      :hit_rate_analytics,
      hit_rate_analytics
    )
    |> assign(
      :hit_rate_p99,
      hit_rate_p99
    )
    |> assign(
      :hit_rate_p90,
      hit_rate_p90
    )
    |> assign(
      :hit_rate_p50,
      hit_rate_p50
    )
    |> assign(
      :selected_hit_rate_type,
      params["hit-rate-type"] || "avg"
    )
    |> assign(
      :analytics_chart_data,
      analytics_chart_data
    )
    |> assign(
      :uri,
      uri
    )
  end

  defp start_date("last_12_months"), do: Date.add(DateTime.utc_now(), -365)
  defp start_date("last_30_days"), do: Date.add(DateTime.utc_now(), -30)
  defp start_date("last_7_days"), do: Date.add(DateTime.utc_now(), -7)

  defp analytics_trend_label("last_7_days"), do: gettext("since last week")
  defp analytics_trend_label("last_12_months"), do: gettext("since last year")
  defp analytics_trend_label(_), do: gettext("since last month")

  defp date_range(params) do
    analytics_date_range = params["analytics_date_range"]

    if is_nil(analytics_date_range) do
      "last_30_days"
    else
      analytics_date_range
    end
  end

  defp analytics_selected_widget(params) do
    analytics_selected_widget = params["analytics_selected_widget"]

    if is_nil(analytics_selected_widget) do
      "cache_hit_rate"
    else
      analytics_selected_widget
    end
  end

  defp assign_recent_builds(%{assigns: %{selected_project: project}} = socket, _params) do
    # Use custom query to filter by cacheable_tasks_count since it's not a Flop filterable field
    base_query =
      from(b in Build,
        where: b.cacheable_tasks_count > 0
      )

    options = %{
      filters: [
        %{field: :project_id, op: :==, value: project.id}
      ],
      order_by: [:inserted_at],
      order_directions: [:desc],
      first: 40,
      for: Build
    }

    # Fetch builds for the chart and table
    {builds, _} =
      base_query
      |> preload(:ran_by_account)
      |> Flop.validate_and_run!(options, for: Build)

    # Prepare chart data for recent builds (use all 40 builds)
    recent_builds_chart_data =
      builds
      |> Enum.reverse()
      |> Enum.map(fn build ->
        hit_rate = cache_hit_rate(build)

        %{
          value: hit_rate,
          date: build.inserted_at,
          itemStyle: %{
            color:
              if hit_rate >= 80 do
                "var(--noora-chart-primary)"
              else
                if hit_rate >= 50 do
                  "var(--noora-chart-warning)"
                else
                  "var(--noora-chart-destructive)"
                end
              end
          }
        }
      end)

    # Calculate average hit rate for display
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
