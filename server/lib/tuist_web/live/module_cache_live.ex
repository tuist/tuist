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
  alias TuistWeb.Utilities.Query

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    slug = "#{account.name}/#{project.name}"

    socket = assign(socket, :head_title, "#{gettext("Module Cache")} · #{slug} · Tuist")

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
          "/#{selected_account.name}/#{selected_project.name}/module-cache?#{Query.put(uri.query, "analytics_selected_widget", widget)}",
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

  def handle_info({:command_event_created, _event}, socket) do
    # Only update when pagination is inactive
    if Query.has_pagination_params?(socket.assigns.uri.query) do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign_analytics(socket.assigns.current_params)
       |> assign_recent_runs(socket.assigns.current_params)}
    end
  end

  def handle_info(_event, socket) do
    {:noreply, socket}
  end

  defp assign_analytics(%{assigns: %{selected_project: project}} = socket, params) do
    date_range = date_range(params)
    start_date = start_date(date_range)
    end_date = Date.utc_today()

    opts = [
      project_id: project.id,
      start_date: start_date,
      end_date: end_date
    ]

    uri = URI.new!("?" <> URI.encode_query(params))

    # Get analytics from Analytics module (runs queries in parallel)
    [hit_rate_analytics, hits_analytics, misses_analytics, hit_rate_p99, hit_rate_p90, hit_rate_p50] =
      combined_module_cache_analytics(project.id, opts)

    analytics_selected_widget = analytics_selected_widget(params)

    analytics_chart_data =
      case analytics_selected_widget do
        "cache_hits" ->
          %{
            dates: hits_analytics.dates,
            values: hits_analytics.values,
            name: gettext("Cache hits"),
            value_formatter: "{value}"
          }

        "cache_misses" ->
          %{
            dates: misses_analytics.dates,
            values: misses_analytics.values,
            name: gettext("Cache misses"),
            value_formatter: "{value}"
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
    |> assign(:analytics_date_range, date_range)
    |> assign(:analytics_trend_label, analytics_trend_label(date_range))
    |> assign(:analytics_selected_widget, analytics_selected_widget)
    |> assign(:hit_rate_analytics, hit_rate_analytics)
    |> assign(:hit_rate_p99, hit_rate_p99)
    |> assign(:hit_rate_p90, hit_rate_p90)
    |> assign(:hit_rate_p50, hit_rate_p50)
    |> assign(:hits_analytics, hits_analytics)
    |> assign(:misses_analytics, misses_analytics)
    |> assign(:selected_hit_rate_type, params["hit-rate-type"] || "avg")
    |> assign(:analytics_chart_data, analytics_chart_data)
    |> assign(:uri, uri)
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

  defp start_date("last_12_months"), do: Date.add(Date.utc_today(), -365)
  defp start_date("last_30_days"), do: Date.add(Date.utc_today(), -30)
  defp start_date("last_7_days"), do: Date.add(Date.utc_today(), -7)

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
