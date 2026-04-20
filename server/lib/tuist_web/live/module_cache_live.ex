defmodule TuistWeb.ModuleCacheLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Ecto.Query
  import TuistWeb.Components.ChartTypeToggle
  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.ScatterChart
  import TuistWeb.Components.Skeleton
  import TuistWeb.PercentileDropdownWidget
  import TuistWeb.Runs.RanByBadge

  alias Phoenix.LiveView.AsyncResult
  alias Tuist.Builds.Analytics
  alias Tuist.CommandEvents
  alias Tuist.CommandEvents.Event
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    slug = "#{account.name}/#{project.name}"

    socket =
      socket
      |> assign(:head_title, "#{dgettext("dashboard_cache", "Module Cache")} · #{slug} · Tuist")
      |> assign(OpenGraph.og_image_assigns("module-cache"))

    {:ok, socket}
  end

  def handle_params(_params, uri, socket) do
    params = Query.query_params(uri)

    uri =
      URI.new!(
        "?" <>
          URI.encode_query(
            Map.take(params, [
              "analytics-selected-widget",
              "analytics-environment",
              "analytics-date-range",
              "analytics-start-date",
              "analytics-end-date",
              "hit-rate-type",
              "cache-hit-rate-chart-type"
            ])
          )
      )

    {
      :noreply,
      socket
      |> assign(:uri, uri)
      |> assign(:current_params, params)
      |> assign_analytics(params)
      |> assign_recent_runs(params)
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
          socket.assigns.hits_analytics.result,
          socket.assigns.misses_analytics.result,
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
          "/#{selected_account.name}/#{selected_project.name}/module-cache?#{Query.put(uri.query, "hit-rate-type", type)}",
        replace: true
      )

    {:noreply, socket}
  end

  def handle_event("select_cache_hit_rate_chart_type", %{"type" => type}, socket) do
    query = Query.put(socket.assigns.uri.query, "cache-hit-rate-chart-type", type)
    uri = URI.new!("?" <> query)
    opts = analytics_opts(socket.assigns)

    {:noreply,
     socket
     |> assign(:cache_hit_rate_chart_type, type)
     |> assign(:uri, uri)
     |> push_event("replace-url", %{url: "?" <> query})
     |> assign_cache_hit_rate_chart(type, opts)}
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

    {:noreply, push_patch(socket, to: "/#{selected_account.name}/#{selected_project.name}/module-cache?#{query_params}")}
  end

  def handle_info(_event, socket) do
    {:noreply, socket}
  end

  defp assign_analytics(%{assigns: %{selected_project: project}} = socket, params) do
    analytics_environment = params["analytics-environment"] || "any"

    %{preset: preset, period: period} = DatePicker.date_picker_params(params, "analytics")

    analytics_selected_widget = params["analytics-selected-widget"] || "cache_hit_rate"
    cache_hit_rate_chart_type = params["cache-hit-rate-chart-type"] || "line"

    socket =
      socket
      |> assign(:analytics_preset, preset)
      |> assign(:analytics_period, period)
      |> assign(:analytics_trend_label, analytics_trend_label(preset))
      |> assign(:analytics_selected_widget, analytics_selected_widget)
      |> assign(:analytics_environment, analytics_environment)
      |> assign(:selected_hit_rate_type, params["hit-rate-type"] || "avg")
      |> assign(:cache_hit_rate_chart_type, cache_hit_rate_chart_type)

    opts = analytics_opts(socket.assigns)

    socket
    |> assign_async([:hit_rate_analytics, :hits_analytics, :misses_analytics, :analytics_chart_data], fn ->
      hit_rate_analytics = Analytics.module_cache_hit_rate_analytics(opts)
      hits_analytics = Analytics.module_cache_hits_analytics(opts)
      misses_analytics = Analytics.module_cache_misses_analytics(opts)

      {:ok,
       %{
         hit_rate_analytics: hit_rate_analytics,
         hits_analytics: hits_analytics,
         misses_analytics: misses_analytics,
         analytics_chart_data:
           analytics_chart_data(
             analytics_selected_widget,
             hits_analytics,
             misses_analytics,
             hit_rate_analytics
           )
       }}
    end)
    |> assign_async(:hit_rate_p99, fn ->
      {:ok, %{hit_rate_p99: Analytics.module_cache_hit_rate_percentile(project.id, 0.99, opts)}}
    end)
    |> assign_async(:hit_rate_p90, fn ->
      {:ok, %{hit_rate_p90: Analytics.module_cache_hit_rate_percentile(project.id, 0.9, opts)}}
    end)
    |> assign_async(:hit_rate_p50, fn ->
      {:ok, %{hit_rate_p50: Analytics.module_cache_hit_rate_percentile(project.id, 0.5, opts)}}
    end)
    |> assign_cache_hit_rate_chart(cache_hit_rate_chart_type, opts)
  end

  defp assign_cache_hit_rate_chart(socket, "scatter", opts) do
    assign_async(socket, :cache_hit_rate_chart, fn ->
      {:ok,
       %{cache_hit_rate_chart: {:scatter, opts |> Analytics.module_cache_hit_rate_scatter_data() |> with_tooltip_extra()}}}
    end)
  end

  defp assign_cache_hit_rate_chart(socket, _line, _opts) do
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

  defp assign_recent_runs(%{assigns: %{selected_project: project}} = socket, _params) do
    assign_async(socket, [:runs, :recent_runs_chart_data, :avg_recent_hit_rate], fn ->
      # Add 14-day filter to leverage ClickHouse partition pruning and reduce rows scanned
      fourteen_days_ago = DateTime.add(DateTime.utc_now(), -14, :day)

      events =
        from(e in {"command_events_by_ran_at", Event},
          where:
            e.project_id == ^project.id and
              e.cacheable_targets_count > 0 and
              e.ran_at >= ^fourteen_days_ago,
          order_by: [desc: e.ran_at],
          limit: 40
        )
        |> Tuist.ClickHouseRepo.all()
        |> Enum.map(&Event.normalize_enums/1)

      user_map = CommandEvents.get_user_account_names_for_runs(events)

      events =
        Enum.map(events, fn event ->
          Map.put(event, :user_account_name, Map.get(user_map, event.id))
        end)

      reversed_events = Enum.reverse(events)

      recent_runs_chart_data =
        Enum.map(reversed_events, fn event ->
          hit_rate = cache_hit_rate(event)

          %{
            value: hit_rate,
            date: event.ran_at,
            url: ~p"/#{project.account.name}/#{project.name}/runs/#{event.id}"
          }
        end)

      avg_recent_hit_rate =
        if Enum.empty?(recent_runs_chart_data) do
          0.0
        else
          total =
            recent_runs_chart_data
            |> Enum.map(& &1.value)
            |> Enum.sum()

          Float.round(total / length(recent_runs_chart_data), 1)
        end

      {:ok,
       %{
         runs: events,
         recent_runs_chart_data: recent_runs_chart_data,
         avg_recent_hit_rate: avg_recent_hit_rate
       }}
    end)
  end

  defp analytics_chart_data("cache_hits", hits_analytics, _misses_analytics, _hit_rate_analytics) do
    %{
      dates: hits_analytics.dates,
      values: hits_analytics.values,
      name: dgettext("dashboard_cache", "Cache hits"),
      value_formatter: "{value}"
    }
  end

  defp analytics_chart_data("cache_misses", _hits_analytics, misses_analytics, _hit_rate_analytics) do
    %{
      dates: misses_analytics.dates,
      values: misses_analytics.values,
      name: dgettext("dashboard_cache", "Cache misses"),
      value_formatter: "{value}"
    }
  end

  defp analytics_chart_data(_cache_hit_rate, _hits_analytics, _misses_analytics, hit_rate_analytics) do
    %{
      dates: hit_rate_analytics.dates,
      values: hit_rate_analytics.values,
      name: dgettext("dashboard_cache", "Cache hit rate"),
      value_formatter: "{value}%"
    }
  end

  def cache_hit_rate(event) do
    total = event.cacheable_targets_count || 0
    local_hits = event.local_cache_hits_count || 0
    remote_hits = event.remote_cache_hits_count || 0

    if total == 0 do
      0.0
    else
      Float.round((local_hits + remote_hits) / total * 100.0, 1)
    end
  end

  defp analytics_trend_label("last-24-hours"), do: dgettext("dashboard_cache", "since yesterday")
  defp analytics_trend_label("last-7-days"), do: dgettext("dashboard_cache", "since last week")
  defp analytics_trend_label("last-12-months"), do: dgettext("dashboard_cache", "since last year")
  defp analytics_trend_label("custom"), do: dgettext("dashboard_cache", "since last period")
  defp analytics_trend_label(_), do: dgettext("dashboard_cache", "since last month")

  defp environment_label("any"), do: dgettext("dashboard_cache", "Any")
  defp environment_label("local"), do: dgettext("dashboard_cache", "Local")
  defp environment_label("ci"), do: dgettext("dashboard_cache", "CI")
  defp environment_label(true), do: dgettext("dashboard_cache", "CI")
  defp environment_label(false), do: dgettext("dashboard_cache", "Local")

  defp with_tooltip_extra(scatter_data) do
    Map.update!(scatter_data, :series, fn series ->
      Enum.map(series, fn s ->
        %{
          name: environment_label(s.name),
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

  defp tooltip_extra(meta) do
    [
      %{label: dgettext("dashboard_cache", "Environment"), value: environment_label(meta.is_ci)}
    ]
  end
end
