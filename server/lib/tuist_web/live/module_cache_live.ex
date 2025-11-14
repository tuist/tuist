defmodule TuistWeb.ModuleCacheLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.PercentileDropdownWidget
  import TuistWeb.Runs.RanByBadge

  alias Tuist.ClickHouseRepo
  alias Tuist.CommandEvents
  alias Tuist.CommandEvents.Event
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

    # Get hit rate data
    hit_rate_result = CommandEvents.cache_hit_rate(project.id, start_date, end_date, opts)
    hit_rate_time_series = CommandEvents.cache_hit_rates(project.id, start_date, end_date, date_period(date_range), time_bucket(date_range), opts)

    # Calculate current hit rate
    cacheable = hit_rate_result.cacheable_targets_count || 0
    local_hits = hit_rate_result.local_cache_hits_count || 0
    remote_hits = hit_rate_result.remote_cache_hits_count || 0
    total_hits = local_hits + remote_hits
    avg_hit_rate = if cacheable == 0, do: 0.0, else: Float.round((total_hits / cacheable) * 100.0, 1)

    # Calculate trend (compare with previous period)
    days_delta = Date.diff(end_date, start_date)
    previous_start = Date.add(start_date, -days_delta)
    previous_result = CommandEvents.cache_hit_rate(project.id, previous_start, start_date, opts)
    previous_cacheable = previous_result.cacheable_targets_count || 0
    previous_hits = (previous_result.local_cache_hits_count || 0) + (previous_result.remote_cache_hits_count || 0)
    previous_hit_rate = if previous_cacheable == 0, do: 0.0, else: Float.round((previous_hits / previous_cacheable) * 100.0, 1)

    hit_rate_trend = calculate_trend(previous_hit_rate, avg_hit_rate)

    # Process hit rate time series
    hit_rate_dates = Enum.map(hit_rate_time_series, & &1.date)
    hit_rate_values = Enum.map(hit_rate_time_series, fn item ->
      cacheable = item.cacheable_targets || 0
      local = item.local_cache_target_hits || 0
      remote = item.remote_cache_target_hits || 0
      if cacheable == 0, do: 0.0, else: Float.round(((local + remote) / cacheable) * 100.0, 1)
    end)

    # Calculate hits analytics
    hits_values = Enum.map(hit_rate_time_series, fn item ->
      (item.local_cache_target_hits || 0) + (item.remote_cache_target_hits || 0)
    end)
    total_hits_count = Enum.sum(hits_values)

    previous_hits_series = CommandEvents.cache_hit_rates(project.id, previous_start, start_date, date_period(date_range), time_bucket(date_range), opts)
    previous_total_hits = Enum.reduce(previous_hits_series, 0, fn item, acc ->
      acc + (item.local_cache_target_hits || 0) + (item.remote_cache_target_hits || 0)
    end)
    hits_trend = calculate_trend(previous_total_hits, total_hits_count)

    # Calculate misses analytics
    misses_values = Enum.map(hit_rate_time_series, fn item ->
      cacheable = item.cacheable_targets || 0
      hits = (item.local_cache_target_hits || 0) + (item.remote_cache_target_hits || 0)
      max(0, cacheable - hits)
    end)
    total_misses_count = Enum.sum(misses_values)

    previous_total_misses = Enum.reduce(previous_hits_series, 0, fn item, acc ->
      cacheable = item.cacheable_targets || 0
      hits = (item.local_cache_target_hits || 0) + (item.remote_cache_target_hits || 0)
      acc + max(0, cacheable - hits)
    end)
    misses_trend = calculate_trend(previous_total_misses, total_misses_count)

    # Get percentile data (p99, p90, p50)
    # Note: For now, we'll use avg for all percentiles since ClickHouse percentile calculation
    # would require more complex queries. This can be enhanced later.
    hit_rate_analytics = %{
      avg_hit_rate: avg_hit_rate,
      trend: hit_rate_trend,
      dates: hit_rate_dates,
      values: hit_rate_values
    }

    hits_analytics = %{
      total_count: total_hits_count,
      trend: hits_trend,
      dates: hit_rate_dates,
      values: hits_values
    }

    misses_analytics = %{
      total_count: total_misses_count,
      trend: misses_trend,
      dates: hit_rate_dates,
      values: misses_values
    }

    analytics_selected_widget = analytics_selected_widget(params)

    analytics_chart_data =
      case analytics_selected_widget do
        "cache_hits" ->
          %{
            dates: hit_rate_dates,
            values: hits_values,
            name: gettext("Cache hits"),
            value_formatter: "{value}"
          }

        "cache_misses" ->
          %{
            dates: hit_rate_dates,
            values: misses_values,
            name: gettext("Cache misses"),
            value_formatter: "{value}"
          }

        "cache_hit_rate" ->
          %{
            dates: hit_rate_dates,
            values: hit_rate_values,
            name: gettext("Cache hit rate"),
            value_formatter: "{value}%"
          }
      end

    socket
    |> assign(:analytics_date_range, date_range)
    |> assign(:analytics_trend_label, analytics_trend_label(date_range))
    |> assign(:analytics_selected_widget, analytics_selected_widget)
    |> assign(:hit_rate_analytics, hit_rate_analytics)
    |> assign(:hit_rate_p99, hit_rate_analytics)
    |> assign(:hit_rate_p90, hit_rate_analytics)
    |> assign(:hit_rate_p50, hit_rate_analytics)
    |> assign(:hits_analytics, hits_analytics)
    |> assign(:misses_analytics, misses_analytics)
    |> assign(:selected_hit_rate_type, params["hit-rate-type"] || "avg")
    |> assign(:analytics_chart_data, analytics_chart_data)
    |> assign(:uri, uri)
  end

  defp assign_recent_runs(%{assigns: %{selected_project: project}} = socket, _params) do
    events =
      from(e in Event,
        where: e.project_id == ^project.id and e.cacheable_targets_count > 0,
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

  defp calculate_trend(previous_value, current_value) do
    case {previous_value, current_value} do
      {0, _} -> 0.0
      {_, 0} -> 0.0
      {0.0, _} -> 0.0
      {_, 0.0} -> 0.0
      {prev, curr} -> Float.round(curr / prev * 100, 1) - 100.0
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

  defp date_period("last_7_days"), do: :day
  defp date_period("last_30_days"), do: :day
  defp date_period("last_12_months"), do: :month

  defp time_bucket("last_7_days"), do: "1 day"
  defp time_bucket("last_30_days"), do: "1 day"
  defp time_bucket("last_12_months"), do: "1 month"

  defp analytics_selected_widget(params) do
    analytics_selected_widget = params["analytics_selected_widget"]

    if is_nil(analytics_selected_widget) do
      "cache_hit_rate"
    else
      analytics_selected_widget
    end
  end
end
