defmodule TuistWeb.TestsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.PercentileDropdownWidget
  import TuistWeb.Runs.RanByBadge

  alias Tuist.Runs
  alias Tuist.Runs.Analytics
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Utilities.Query

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    socket =
      socket
      |> assign(
        :head_title,
        "#{dgettext("dashboard_tests", "Tests")} · #{account.name}/#{project.name} · Tuist"
      )
      |> assign_recent_test_runs()
      |> assign_slowest_test_cases()

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
              "analytics-environment",
              "analytics-date-range",
              "analytics-selected-widget",
              "duration-type",
              "selective-testing-environment",
              "selective-testing-date-range",
              "selective-testing-duration-type"
            ])
          )
      )

    {
      :noreply,
      socket
      |> assign(:uri, uri)
      |> assign(:current_params, params)
      |> assign_analytics(params)
      |> assign_selective_testing(params)
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
          "/#{selected_account.name}/#{selected_project.name}/tests?#{Query.put(uri.query, "analytics-selected-widget", widget)}",
        replace: true
      )

    {:noreply, socket}
  end

  def handle_event(
        "select_duration_type",
        %{"type" => type},
        %{assigns: %{selected_account: selected_account, selected_project: selected_project, uri: uri}} = socket
      ) do
    query =
      uri.query
      |> Query.put("duration-type", type)
      |> Query.put("analytics-selected-widget", "test_run_duration")

    socket =
      push_patch(
        socket,
        to: "/#{selected_account.name}/#{selected_project.name}/tests?#{query}",
        replace: true
      )

    {:noreply, socket}
  end

  def handle_event(
        "select_selective_testing_duration_type",
        %{"type" => type},
        %{assigns: %{selected_account: selected_account, selected_project: selected_project, uri: uri}} = socket
      ) do
    socket =
      push_patch(
        socket,
        to:
          "/#{selected_account.name}/#{selected_project.name}/tests?#{Query.put(uri.query, "selective-testing-duration-type", type)}",
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

    {:noreply, push_patch(socket, to: "/#{selected_account.name}/#{selected_project.name}/tests?#{query_params}")}
  end

  def handle_event(
        "selective_testing_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        %{assigns: %{selected_account: selected_account, selected_project: selected_project}} = socket
      ) do
    query_params =
      if preset == "custom" do
        socket.assigns.uri.query
        |> Query.put("selective-testing-date-range", "custom")
        |> Query.put("selective-testing-start-date", start_date)
        |> Query.put("selective-testing-end-date", end_date)
      else
        Query.put(socket.assigns.uri.query, "selective-testing-date-range", preset)
      end

    {:noreply, push_patch(socket, to: "/#{selected_account.name}/#{selected_project.name}/tests?#{query_params}")}
  end

  def handle_info({:test_created, %{name: "test"}}, socket) do
    if Query.has_pagination_params?(socket.assigns.uri.query) do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign_analytics(socket.assigns.current_params)
       |> assign_selective_testing(socket.assigns.current_params)
       |> assign_recent_test_runs()
       |> assign_slowest_test_cases()}
    end
  end

  def handle_info(_event, socket) do
    {:noreply, socket}
  end

  defp assign_analytics(%{assigns: %{selected_project: project}} = socket, params) do
    analytics_environment = params["analytics-environment"] || "any"
    analytics_selected_widget = params["analytics-selected-widget"] || "test_run_count"
    selected_duration_type = params["duration-type"] || "avg"

    %{preset: preset, period: {start_datetime, end_datetime} = period} =
      DatePicker.date_picker_params(params, "analytics")

    opts = [start_datetime: start_datetime, end_datetime: end_datetime]

    opts =
      case analytics_environment do
        "ci" -> Keyword.put(opts, :is_ci, true)
        "local" -> Keyword.put(opts, :is_ci, false)
        _ -> opts
      end

    [test_runs_analytics, failed_test_runs_analytics, test_runs_duration_analytics] =
      Task.await_many(
        [
          Task.async(fn -> Analytics.test_run_analytics(project.id, opts) end),
          Task.async(fn -> Analytics.test_run_analytics(project.id, Keyword.put(opts, :status, "failure")) end),
          Task.async(fn -> Analytics.test_run_duration_analytics(project.id, opts) end)
        ],
        30_000
      )

    socket
    |> assign(:test_runs_analytics, test_runs_analytics)
    |> assign(:failed_test_runs_analytics, failed_test_runs_analytics)
    |> assign(:test_runs_duration_analytics, test_runs_duration_analytics)
    |> assign(:analytics_environment, analytics_environment)
    |> assign(:analytics_environment_label, environment_label(analytics_environment))
    |> assign(:analytics_preset, preset)
    |> assign(:analytics_period, period)
    |> assign(:analytics_trend_label, trend_label(preset))
    |> assign(:analytics_selected_widget, analytics_selected_widget)
    |> assign(:selected_duration_type, selected_duration_type)
  end

  defp assign_selective_testing(%{assigns: %{selected_project: project}} = socket, params) do
    selective_testing_environment = params["selective-testing-environment"] || "any"
    selective_testing_duration_type = params["selective-testing-duration-type"] || "avg"

    %{preset: preset, period: {start_datetime, end_datetime} = period} =
      DatePicker.date_picker_params(params, "selective-testing")

    opts = [project_id: project.id, start_datetime: start_datetime, end_datetime: end_datetime]

    opts =
      case selective_testing_environment do
        "ci" -> Keyword.put(opts, :is_ci, true)
        "local" -> Keyword.put(opts, :is_ci, false)
        _ -> opts
      end

    selective_testing_analytics = Analytics.selective_testing_analytics_with_percentiles(opts)

    socket
    |> assign(:selective_testing_analytics, selective_testing_analytics)
    |> assign(:selective_testing_environment, selective_testing_environment)
    |> assign(:selective_testing_environment_label, environment_label(selective_testing_environment))
    |> assign(:selective_testing_preset, preset)
    |> assign(:selective_testing_period, period)
    |> assign(:selective_testing_duration_type, selective_testing_duration_type)
  end

  defp assign_recent_test_runs(%{assigns: %{selected_project: project}} = socket) do
    {recent_test_runs, _meta} =
      Runs.list_test_runs(%{
        last: 40,
        filters: [
          %{field: :project_id, op: :==, value: project.id}
        ],
        order_by: [:ran_at],
        order_directions: [:asc]
      })

    recent_test_runs_chart_data =
      Enum.map(recent_test_runs, fn run ->
        color =
          case run.status do
            "success" -> "var:noora-chart-primary"
            "failure" -> "var:noora-chart-destructive"
            "skipped" -> "var:noora-chart-warning"
          end

        value = (run.duration / 1000) |> Decimal.from_float() |> Decimal.round(0)

        %{value: value, itemStyle: %{color: color}, date: run.ran_at}
      end)

    failed_test_runs_count = Enum.count(recent_test_runs, fn run -> run.status == "failure" end)
    passed_test_runs_count = Enum.count(recent_test_runs, fn run -> run.status == "success" end)

    socket
    |> assign(:recent_test_runs, recent_test_runs)
    |> assign(:recent_test_runs_chart_data, recent_test_runs_chart_data)
    |> assign(:failed_test_runs_count, failed_test_runs_count)
    |> assign(:passed_test_runs_count, passed_test_runs_count)
  end

  defp assign_slowest_test_cases(%{assigns: %{selected_project: project}} = socket) do
    {slowest_test_cases, _meta} =
      Runs.list_test_cases(project.id, %{
        page: 1,
        page_size: 5,
        order_by: [:avg_duration],
        order_directions: [:desc]
      })

    assign(socket, :slowest_test_cases, slowest_test_cases)
  end

  defp trend_label("last-24-hours"), do: dgettext("dashboard_tests", "since yesterday")
  defp trend_label("last-7-days"), do: dgettext("dashboard_tests", "since last week")
  defp trend_label("last-12-months"), do: dgettext("dashboard_tests", "since last year")
  defp trend_label("custom"), do: dgettext("dashboard_tests", "since last period")
  defp trend_label(_), do: dgettext("dashboard_tests", "since last month")

  defp environment_label("any"), do: dgettext("dashboard_tests", "Any")
  defp environment_label("local"), do: dgettext("dashboard_tests", "Local")
  defp environment_label("ci"), do: dgettext("dashboard_tests", "CI")
end
