defmodule TuistWeb.OnceTestsLive do
  @moduledoc """
  Once tests dashboard. Mirrors `TuistWeb.TestsLive` markup 1:1 — same
  container id, same `data-part` values — so `tests_live.css` styles it
  identically. The data source is `Tuist.OnceEvents.Analytics` scoped
  to test runs.
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.BazelAnalyticsHelpers
  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.Skeleton
  import TuistWeb.PercentileDropdownWidget

  alias Phoenix.LiveView.AsyncResult
  alias Tuist.OnceEvents
  alias Tuist.OnceEvents.Analytics
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Utilities.Query

  @recent_run_limit 40

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    socket =
      assign(socket, :head_title, "#{dgettext("dashboard_tests", "Tests")} · #{account.name}/#{project.name} · Tuist")

    if connected?(socket) do
      OnceEvents.subscribe_project(project.id)
    end

    {:ok, socket}
  end

  def handle_params(params, _uri, %{assigns: %{selected_project: project}} = socket) do
    uri = URI.new!("?" <> URI.encode_query(params))

    %{preset: analytics_preset, period: analytics_period} =
      DatePicker.date_picker_params(params, "analytics")

    analytics_selected_widget = params["analytics-selected-widget"] || "test_run_count"
    selected_duration_type = params["duration-type"] || "avg"

    commands = ["test"]
    opts = analytics_opts(analytics_period, commands)

    socket =
      socket
      |> assign(:uri, uri)
      |> assign(:analytics_preset, analytics_preset)
      |> assign(:analytics_period, analytics_period)
      |> assign(:analytics_trend_label, analytics_trend_label(analytics_preset))
      |> assign(:analytics_selected_widget, analytics_selected_widget)
      |> assign(:selected_duration_type, selected_duration_type)
      |> assign_async(
        [
          :test_runs_analytics,
          :flaky_test_runs_analytics,
          :failed_test_runs_analytics,
          :test_runs_duration_analytics,
          :analytics_series,
          :analytics_chart_data
        ],
        fn ->
          analytics_bundle(project.id, analytics_period, commands, analytics_selected_widget, selected_duration_type)
        end
      )
      |> assign_async(
        [
          :recent_test_runs,
          :recent_test_runs_chart_data,
          :failed_test_runs_count,
          :passed_test_runs_count
        ],
        fn -> recent_bundle(project.id, opts) end
      )

    {:noreply, socket}
  end

  def handle_info({:run_updated, _run_id}, socket) do
    params = URI.decode_query(socket.assigns.uri.query || "")
    handle_params(params, nil, socket)
  end

  def handle_event("select_widget", %{"widget" => widget}, socket) do
    query = Query.put(socket.assigns.uri.query, "analytics-selected-widget", widget)

    {:noreply,
     socket
     |> assign(:analytics_selected_widget, widget)
     |> assign(:uri, URI.new!("?" <> query))
     |> push_event("replace-url", %{url: "?" <> query})
     |> refresh_chart_data()}
  end

  def handle_event("select_duration_type", %{"type" => type}, socket) do
    query =
      socket.assigns.uri.query
      |> Query.put("duration-type", type)
      |> Query.put("analytics-selected-widget", "test_run_duration")

    {:noreply,
     socket
     |> assign(:selected_duration_type, type)
     |> assign(:analytics_selected_widget, "test_run_duration")
     |> assign(:uri, URI.new!("?" <> query))
     |> push_event("replace-url", %{url: "?" <> query})
     |> refresh_chart_data()}
  end

  def handle_event(
        "analytics_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        socket
      ) do
    query =
      if preset == "custom" do
        socket.assigns.uri.query
        |> Query.put("analytics-date-range", "custom")
        |> Query.put("analytics-start-date", start_date)
        |> Query.put("analytics-end-date", end_date)
      else
        Query.put(socket.assigns.uri.query, "analytics-date-range", preset)
      end

    {:noreply, push_patch(socket, to: current_path(socket, URI.decode_query(query)))}
  end

  # ---- Async bundles ---------------------------------------------------

  defp analytics_bundle(project_id, period, commands, widget, duration_type) do
    summary = summary_with_trends(project_id, period, commands)
    time_series = Analytics.invocation_analytics(project_id, analytics_opts(period, commands))

    test_runs_analytics = %{count: to_number(summary.total), trend: summary.total_trend}

    failed_test_runs_analytics = %{
      count: to_number(summary.failed),
      trend: summary.failed_trend
    }

    flaky_test_runs_analytics = %{count: 0, trend: 0.0}

    test_runs_duration_analytics = %{
      total_average_duration: to_number(summary.average_duration_ms),
      p50: to_number(summary.median_duration_ms),
      p90: to_number(summary.p90_duration_ms),
      p99: to_number(summary.p99_duration_ms),
      trend: summary.average_duration_trend,
      dates: time_series.dates,
      values: time_series.average_duration_values,
      p50_values: time_series.median_duration_values,
      p90_values: time_series.p90_duration_values,
      p99_values: time_series.p99_duration_values
    }

    {:ok,
     %{
       test_runs_analytics: test_runs_analytics,
       flaky_test_runs_analytics: flaky_test_runs_analytics,
       failed_test_runs_analytics: failed_test_runs_analytics,
       test_runs_duration_analytics: test_runs_duration_analytics,
       analytics_series: time_series,
       analytics_chart_data: chart_data(time_series, widget, duration_type)
     }}
  end

  defp recent_bundle(project_id, opts) do
    {runs, _meta} =
      Analytics.list_invocations(
        project_id,
        %{page: 1, page_size: @recent_run_limit, order_by: [:finished_at], order_directions: [:asc]},
        opts
      )

    chart_data =
      Enum.map(runs, fn run ->
        color =
          case run.status do
            "success" -> "var:noora-chart-primary"
            "failure" -> "var:noora-chart-destructive"
            _ -> "var:noora-chart-primary"
          end

        %{
          value: div(run.duration_ms || 0, 1000),
          itemStyle: %{color: color},
          date: run.finished_at
        }
      end)

    failed = Enum.count(runs, fn run -> run.status == "failure" end)
    passed = Enum.count(runs, fn run -> run.status == "success" end)

    {:ok,
     %{
       recent_test_runs: runs,
       recent_test_runs_chart_data: chart_data,
       failed_test_runs_count: failed,
       passed_test_runs_count: passed
     }}
  end

  # ---- Rendering helpers used in the template --------------------------

  def duration_title("p99"), do: dgettext("dashboard_tests", "p99 test run duration")
  def duration_title("p90"), do: dgettext("dashboard_tests", "p90 test run duration")
  def duration_title("p50"), do: dgettext("dashboard_tests", "p50 test run duration")
  def duration_title(_), do: dgettext("dashboard_tests", "Avg. test run duration")

  def duration_legend_color("p99"), do: "p99"
  def duration_legend_color("p90"), do: "p90"
  def duration_legend_color("p50"), do: "p50"
  def duration_legend_color(_), do: "secondary"

  def duration_value(result, "p99"), do: result.p99
  def duration_value(result, "p90"), do: result.p90
  def duration_value(result, "p50"), do: result.p50
  def duration_value(result, _), do: result.total_average_duration

  def duration_metrics(result) do
    %{
      avg: DateFormatter.format_duration_from_milliseconds(result.total_average_duration),
      p99: DateFormatter.format_duration_from_milliseconds(result.p99),
      p90: DateFormatter.format_duration_from_milliseconds(result.p90),
      p50: DateFormatter.format_duration_from_milliseconds(result.p50)
    }
  end

  def run_detail_path(assigns, run) do
    ~p"/#{assigns.selected_account.name}/#{assigns.selected_project.name}/once/test-runs/#{run.invocation_id}"
  end

  def test_runs_list_path(assigns) do
    ~p"/#{assigns.selected_account.name}/#{assigns.selected_project.name}/once/test-runs"
  end

  # ---- Internals -------------------------------------------------------

  defp summary_with_trends(project_id, {start_dt, end_dt}, commands) do
    current = Analytics.summary(project_id, analytics_opts({start_dt, end_dt}, commands))
    {prev_start, prev_end} = previous_period(start_dt, end_dt)
    previous = Analytics.summary(project_id, analytics_opts({prev_start, prev_end}, commands))

    Map.merge(current, %{
      total_trend: trend(previous.total, current.total),
      failed_trend: trend(previous.failed, current.failed),
      average_duration_trend: trend(previous.average_duration_ms, current.average_duration_ms),
      median_duration_trend: trend(previous.median_duration_ms, current.median_duration_ms),
      p90_duration_trend: trend(previous.p90_duration_ms, current.p90_duration_ms),
      p99_duration_trend: trend(previous.p99_duration_ms, current.p99_duration_ms)
    })
  end

  defp analytics_opts(period, commands) do
    period
    |> period_opts()
    |> Keyword.put(:commands, commands)
  end

  # Selecting a widget only swaps which series the one chart renders, so it
  # is re-derived from the series already in hand rather than re-queried.
  # Without this the chart kept the previous metric's values under the new
  # label until something else triggered `handle_params/3`.
  defp refresh_chart_data(%{assigns: %{analytics_series: %{ok?: true, result: series}}} = socket) do
    data = chart_data(series, socket.assigns.analytics_selected_widget, socket.assigns.selected_duration_type)

    assign(socket, :analytics_chart_data, AsyncResult.ok(socket.assigns.analytics_chart_data, data))
  end

  defp refresh_chart_data(socket), do: socket

  defp chart_data(time_series, widget, duration_type) do
    %{dates: time_series.dates, values: values_for_widget(time_series, widget, duration_type)}
  end

  defp values_for_widget(time_series, "failed_test_run_count", _duration), do: time_series.failed_values
  defp values_for_widget(time_series, "test_run_duration", "p50"), do: time_series.median_duration_values
  defp values_for_widget(time_series, "test_run_duration", "p90"), do: time_series.p90_duration_values
  defp values_for_widget(time_series, "test_run_duration", "p99"), do: time_series.p99_duration_values
  defp values_for_widget(time_series, "test_run_duration", _duration), do: time_series.average_duration_values

  defp values_for_widget(time_series, "flaky_test_run_count", _duration), do: Enum.map(time_series.dates, fn _ -> 0 end)

  defp values_for_widget(time_series, _widget, _duration), do: time_series.total_values

  defp to_number(nil), do: 0
  defp to_number(%Decimal{} = value), do: Decimal.to_float(value)
  defp to_number(value) when is_number(value), do: value

  defp current_path(socket, params) do
    query = URI.encode_query(params)

    ~p"/#{socket.assigns.selected_account.name}/#{socket.assigns.selected_project.name}/once/tests" <>
      "?" <> query
  end
end
