defmodule TuistWeb.ModuleCacheLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.PercentileDropdownWidget
  import TuistWeb.Runs.RanByBadge

  alias Tuist.CommandEvents
  alias Tuist.CommandEvents.Event
  alias Tuist.Runs.Analytics
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Utilities.Query

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    slug = "#{account.name}/#{project.name}"

    socket = assign(socket, :head_title, "#{dgettext("dashboard_cache", "Module Cache")} · #{slug} · Tuist")

    if connected?(socket) do
      Tuist.PubSub.subscribe("#{account.name}/#{project.name}")
    end

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    uri =
      URI.new!(
        "?" <>
          URI.encode_query(
            Map.take(params, [
              "analytics-selected-widget",
              "analytics-environment",
              "analytics-date-range",
              "hit-rate-type"
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

  def handle_event(
        "select_widget",
        %{"widget" => widget},
        %{assigns: %{selected_account: selected_account, selected_project: selected_project, uri: uri}} = socket
      ) do
    socket =
      push_patch(
        socket,
        to:
          "/#{selected_account.name}/#{selected_project.name}/module-cache?#{Query.put(uri.query, "analytics-selected-widget", widget)}",
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
          "/#{selected_account.name}/#{selected_project.name}/module-cache?#{Query.put(uri.query, "hit-rate-type", type)}",
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

    {:noreply, push_patch(socket, to: "/#{selected_account.name}/#{selected_project.name}/module-cache?#{query_params}")}
  end

  def handle_info({:command_event_created, _event}, socket) do
    {:noreply,
     socket
     |> assign_analytics(socket.assigns.current_params)
     |> assign_recent_runs(socket.assigns.current_params)}
  end

  def handle_info(_event, socket) do
    {:noreply, socket}
  end

  defp assign_analytics(%{assigns: %{selected_project: project}} = socket, params) do
    analytics_environment = params["analytics-environment"] || "any"

    %{preset: preset, period: {start_datetime, end_datetime} = period} =
      DatePicker.date_picker_params(params, "analytics")

    opts = [
      project_id: project.id,
      start_datetime: start_datetime,
      end_datetime: end_datetime
    ]

    opts =
      case analytics_environment do
        "ci" -> Keyword.put(opts, :is_ci, true)
        "local" -> Keyword.put(opts, :is_ci, false)
        _ -> opts
      end

    # Get analytics from Analytics module (runs queries in parallel)
    [hit_rate_analytics, hits_analytics, misses_analytics, hit_rate_p99, hit_rate_p90, hit_rate_p50] =
      combined_module_cache_analytics(project.id, opts)

    analytics_selected_widget = params["analytics-selected-widget"] || "cache_hit_rate"

    analytics_chart_data =
      case analytics_selected_widget do
        "cache_hits" ->
          %{
            dates: hits_analytics.dates,
            values: hits_analytics.values,
            name: dgettext("dashboard_cache", "Cache hits"),
            value_formatter: "{value}"
          }

        "cache_misses" ->
          %{
            dates: misses_analytics.dates,
            values: misses_analytics.values,
            name: dgettext("dashboard_cache", "Cache misses"),
            value_formatter: "{value}"
          }

        "cache_hit_rate" ->
          %{
            dates: hit_rate_analytics.dates,
            values: hit_rate_analytics.values,
            name: dgettext("dashboard_cache", "Cache hit rate"),
            value_formatter: "{value}%"
          }
      end

    socket
    |> assign(:analytics_preset, preset)
    |> assign(:analytics_period, period)
    |> assign(:analytics_trend_label, analytics_trend_label(preset))
    |> assign(:analytics_selected_widget, analytics_selected_widget)
    |> assign(:analytics_environment, analytics_environment)
    |> assign(:hit_rate_analytics, hit_rate_analytics)
    |> assign(:hit_rate_p99, hit_rate_p99)
    |> assign(:hit_rate_p90, hit_rate_p90)
    |> assign(:hit_rate_p50, hit_rate_p50)
    |> assign(:hits_analytics, hits_analytics)
    |> assign(:misses_analytics, misses_analytics)
    |> assign(:selected_hit_rate_type, params["hit-rate-type"] || "avg")
    |> assign(:analytics_chart_data, analytics_chart_data)
  end

  defp assign_recent_runs(%{assigns: %{selected_project: project}} = socket, _params) do
    options = %{
      filters: [
        %{field: :project_id, op: :==, value: project.id},
        %{field: :cacheable_targets_count, op: :>, value: 0}
      ],
      order_by: [:ran_at],
      order_directions: [:desc],
      first: 40,
      for: Event
    }

    {events, _} = Tuist.ClickHouseFlop.validate_and_run!(Event, options, for: Event)

    events = Enum.map(events, &Event.normalize_enums/1)

    user_map = CommandEvents.get_user_account_names_for_runs(events)

    events =
      Enum.map(events, fn event ->
        Map.put(event, :user_account_name, Map.get(user_map, event.id))
      end)

    recent_runs_chart_data =
      events
      |> Enum.reverse()
      |> Enum.map(fn event ->
        hit_rate = cache_hit_rate(event)

        %{
          value: hit_rate,
          date: event.ran_at
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

    socket
    |> assign(:runs, events)
    |> assign(:recent_runs_chart_data, recent_runs_chart_data)
    |> assign(:avg_recent_hit_rate, avg_recent_hit_rate)
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

  defp combined_module_cache_analytics(project_id, opts) do
    queries = [
      fn -> Analytics.module_cache_hit_rate_analytics(opts) end,
      fn -> Analytics.module_cache_hits_analytics(opts) end,
      fn -> Analytics.module_cache_misses_analytics(opts) end,
      fn -> Analytics.module_cache_hit_rate_percentile(project_id, 0.99, opts) end,
      fn -> Analytics.module_cache_hit_rate_percentile(project_id, 0.9, opts) end,
      fn -> Analytics.module_cache_hit_rate_percentile(project_id, 0.5, opts) end
    ]

    Tuist.Tasks.parallel_tasks(queries)
  end
end
