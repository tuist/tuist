defmodule TuistWeb.TestsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.ChartTypeToggle
  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.ScatterChart
  import TuistWeb.Components.Skeleton
  import TuistWeb.Helpers.TestLabels
  import TuistWeb.PercentileDropdownWidget
  import TuistWeb.Runs.RanByBadge

  alias Phoenix.LiveView.AsyncResult
  alias Tuist.Builds.Analytics, as: BuildsAnalytics
  alias Tuist.Tests
  alias Tuist.Tests.Analytics
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    socket =
      socket
      |> assign(
        :head_title,
        "#{dgettext("dashboard_tests", "Tests")} · #{account.name}/#{project.name} · Tuist"
      )
      |> assign(OpenGraph.og_image_assigns("tests"))
      |> assign_recent_test_runs()
      |> assign_slowest_test_cases()
      |> assign_most_flaky_test_cases()

    if connected?(socket) do
      Tuist.PubSub.subscribe("#{account.name}/#{project.name}")
    end

    {:ok, socket}
  end

  def handle_params(_params, uri, socket) do
    params = Query.query_params(uri)

    uri =
      URI.new!(
        "?" <>
          URI.encode_query(
            Map.take(params, [
              "analytics-environment",
              "analytics-test-scheme",
              "analytics-date-range",
              "analytics-start-date",
              "analytics-end-date",
              "analytics-selected-widget",
              "duration-type",
              "duration-chart-type",
              "duration-scatter-group-by",
              "selective-testing-environment",
              "selective-testing-date-range",
              "selective-testing-start-date",
              "selective-testing-end-date",
              "selective-testing-duration-type",
              "selective-testing-chart-type"
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

  def handle_event("select_widget", %{"widget" => widget}, socket) do
    query = Query.put(socket.assigns.uri.query, "analytics-selected-widget", widget)
    uri = URI.new!("?" <> query)

    socket =
      socket
      |> assign(:analytics_selected_widget, widget)
      |> assign(:uri, uri)
      |> push_event("replace-url", %{url: "?" <> query})

    if socket.assigns.test_runs_analytics.ok? do
      chart_data =
        analytics_chart_data(
          widget,
          socket.assigns.selected_duration_type,
          socket.assigns.test_runs_analytics.result,
          socket.assigns.flaky_test_runs_analytics.result,
          socket.assigns.failed_test_runs_analytics.result,
          socket.assigns.test_runs_duration_analytics.result
        )

      {:noreply, assign(socket, :analytics_chart_data, %{socket.assigns.analytics_chart_data | result: chart_data})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("select_duration_type", %{"type" => type}, socket) do
    query =
      socket.assigns.uri.query
      |> Query.put("duration-type", type)
      |> Query.put("analytics-selected-widget", "test_run_duration")

    uri = URI.new!("?" <> query)

    socket =
      socket
      |> assign(:selected_duration_type, type)
      |> assign(:analytics_selected_widget, "test_run_duration")
      |> assign(:uri, uri)
      |> push_event("replace-url", %{url: "?" <> query})

    if socket.assigns.test_runs_analytics.ok? do
      chart_data =
        analytics_chart_data(
          "test_run_duration",
          type,
          socket.assigns.test_runs_analytics.result,
          socket.assigns.flaky_test_runs_analytics.result,
          socket.assigns.failed_test_runs_analytics.result,
          socket.assigns.test_runs_duration_analytics.result
        )

      {:noreply, assign(socket, :analytics_chart_data, %{socket.assigns.analytics_chart_data | result: chart_data})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("select_duration_chart_type", %{"type" => type}, socket) do
    query = Query.put(socket.assigns.uri.query, "duration-chart-type", type)
    uri = URI.new!("?" <> query)
    socket = assign(socket, duration_chart_type: type, uri: uri)
    opts = duration_opts(socket.assigns)
    group_by = duration_scatter_group_by_atom(socket.assigns.duration_scatter_group_by)

    {:noreply,
     socket
     |> push_event("replace-url", %{url: "?" <> query})
     |> assign_test_run_duration_chart(type, group_by, opts)}
  end

  def handle_event("select_selective_testing_chart_type", %{"type" => type}, socket) do
    query = Query.put(socket.assigns.uri.query, "selective-testing-chart-type", type)
    uri = URI.new!("?" <> query)
    socket = assign(socket, selective_testing_chart_type: type, uri: uri)
    opts = selective_testing_opts(socket.assigns)

    {:noreply,
     socket
     |> push_event("replace-url", %{url: "?" <> query})
     |> assign_selective_testing_chart(type, opts)}
  end

  def handle_event("select_selective_testing_duration_type", %{"type" => type}, socket) do
    query = Query.put(socket.assigns.uri.query, "selective-testing-duration-type", type)
    uri = URI.new!("?" <> query)

    {:noreply,
     socket
     |> assign(:selective_testing_duration_type, type)
     |> assign(:uri, uri)
     |> push_event("replace-url", %{url: "?" <> query})}
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
       |> assign_slowest_test_cases()
       |> assign_most_flaky_test_cases()}
    end
  end

  def handle_info(_event, socket) do
    {:noreply, socket}
  end

  defp assign_analytics(%{assigns: %{selected_project: project}} = socket, params) do
    analytics_environment = params["analytics-environment"] || "any"
    analytics_test_scheme = params["analytics-test-scheme"] || "any"
    analytics_selected_widget = params["analytics-selected-widget"] || "test_run_count"
    selected_duration_type = params["duration-type"] || "avg"
    duration_chart_type = params["duration-chart-type"] || "line"
    duration_scatter_group_by = params["duration-scatter-group-by"] || "scheme"

    %{preset: preset, period: period} = DatePicker.date_picker_params(params, "analytics")

    socket =
      socket
      |> assign(:analytics_environment, analytics_environment)
      |> assign(:analytics_environment_label, environment_label(analytics_environment))
      |> assign(:analytics_test_scheme, analytics_test_scheme)
      |> assign(:test_schemes, Tests.project_test_schemes(project))
      |> assign(:analytics_preset, preset)
      |> assign(:analytics_period, period)
      |> assign(:analytics_trend_label, trend_label(preset))
      |> assign(:analytics_selected_widget, analytics_selected_widget)
      |> assign(:selected_duration_type, selected_duration_type)
      |> assign(:duration_chart_type, duration_chart_type)
      |> assign(:duration_scatter_group_by, duration_scatter_group_by)

    opts = duration_opts(socket.assigns)
    scatter_group_by_atom = duration_scatter_group_by_atom(duration_scatter_group_by)

    socket
    |> assign_test_run_duration_chart(duration_chart_type, scatter_group_by_atom, opts)
    |> assign_async(
      [
        :test_runs_analytics,
        :flaky_test_runs_analytics,
        :failed_test_runs_analytics,
        :test_runs_duration_analytics,
        :analytics_chart_data
      ],
      fn ->
        test_runs_analytics = Analytics.test_run_analytics(project.id, opts)

        flaky_test_runs_analytics =
          Analytics.test_run_analytics(project.id, Keyword.put(opts, :is_flaky, true))

        failed_test_runs_analytics =
          Analytics.test_run_analytics(project.id, Keyword.put(opts, :status, "failure"))

        test_runs_duration_analytics = Analytics.test_run_duration_analytics(project.id, opts)

        {:ok,
         %{
           test_runs_analytics: test_runs_analytics,
           flaky_test_runs_analytics: flaky_test_runs_analytics,
           failed_test_runs_analytics: failed_test_runs_analytics,
           test_runs_duration_analytics: test_runs_duration_analytics,
           analytics_chart_data:
             analytics_chart_data(
               analytics_selected_widget,
               selected_duration_type,
               test_runs_analytics,
               flaky_test_runs_analytics,
               failed_test_runs_analytics,
               test_runs_duration_analytics
             )
         }}
      end
    )
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

    selective_testing_chart_type = params["selective-testing-chart-type"] || "line"

    socket
    |> assign(:selective_testing_environment, selective_testing_environment)
    |> assign(:selective_testing_environment_label, environment_label(selective_testing_environment))
    |> assign(:selective_testing_preset, preset)
    |> assign(:selective_testing_period, period)
    |> assign(:selective_testing_duration_type, selective_testing_duration_type)
    |> assign(:selective_testing_chart_type, selective_testing_chart_type)
    |> assign_async(:selective_testing_analytics, fn ->
      {:ok, %{selective_testing_analytics: BuildsAnalytics.selective_testing_analytics_with_percentiles(opts)}}
    end)
    |> assign_selective_testing_chart(selective_testing_chart_type, opts)
  end

  defp assign_recent_test_runs(%{assigns: %{selected_project: project}} = socket) do
    assign_async(
      socket,
      [
        :recent_test_runs,
        :recent_test_runs_chart_data,
        :failed_test_runs_count,
        :passed_test_runs_count
      ],
      fn ->
        {recent_test_runs, _meta} =
          Tests.list_test_runs(%{
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
              cond do
                run.status == "success" -> "var:noora-chart-primary"
                run.status == "failure" -> "var:noora-chart-destructive"
                run.status == "skipped" -> "var:noora-chart-warning"
                true -> "var:noora-chart-primary"
              end

            value = (run.duration / 1000) |> Decimal.from_float() |> Decimal.round(0)

            %{
              value: value,
              itemStyle: %{color: color},
              date: run.ran_at,
              url: ~p"/#{project.account.name}/#{project.name}/tests/test-runs/#{run.id}"
            }
          end)

        failed_test_runs_count = Enum.count(recent_test_runs, fn run -> run.status == "failure" end)
        passed_test_runs_count = Enum.count(recent_test_runs, fn run -> run.status == "success" end)

        {:ok,
         %{
           recent_test_runs: recent_test_runs,
           recent_test_runs_chart_data: recent_test_runs_chart_data,
           failed_test_runs_count: failed_test_runs_count,
           passed_test_runs_count: passed_test_runs_count
         }}
      end
    )
  end

  defp assign_slowest_test_cases(%{assigns: %{selected_project: project}} = socket) do
    assign_async(socket, :slowest_test_cases, fn ->
      # `:id` tiebreaker keeps the top-5 order deterministic when several
      # test cases share the same avg_duration.
      {slowest_test_cases, _meta} =
        Tests.list_test_cases(project.id, %{
          page: 1,
          page_size: 5,
          order_by: [:avg_duration, :id],
          order_directions: [:desc, :asc]
        })

      {:ok, %{slowest_test_cases: slowest_test_cases}}
    end)
  end

  defp assign_most_flaky_test_cases(%{assigns: %{selected_project: project}} = socket) do
    assign_async(socket, :most_flaky_test_cases, fn ->
      {most_flaky_test_cases, _meta} =
        Tests.list_flaky_test_cases(project.id, %{
          page: 1,
          page_size: 5,
          order_by: [:flaky_runs_count],
          order_directions: [:desc]
        })

      {:ok, %{most_flaky_test_cases: most_flaky_test_cases}}
    end)
  end

  defp analytics_chart_data(
         analytics_selected_widget,
         selected_duration_type,
         test_runs_analytics,
         flaky_test_runs_analytics,
         failed_test_runs_analytics,
         test_runs_duration_analytics
       ) do
    case analytics_selected_widget do
      "test_run_count" ->
        %{dates: test_runs_analytics.dates, values: test_runs_analytics.values}

      "flaky_test_run_count" ->
        %{dates: flaky_test_runs_analytics.dates, values: flaky_test_runs_analytics.values}

      "failed_test_run_count" ->
        %{dates: failed_test_runs_analytics.dates, values: failed_test_runs_analytics.values}

      _ ->
        values =
          case selected_duration_type do
            "p99" -> test_runs_duration_analytics.p99_values
            "p90" -> test_runs_duration_analytics.p90_values
            "p50" -> test_runs_duration_analytics.p50_values
            _ -> test_runs_duration_analytics.values
          end

        %{dates: test_runs_duration_analytics.dates, values: values}
    end
  end

  defp trend_label("last-24-hours"), do: dgettext("dashboard_tests", "since yesterday")
  defp trend_label("last-7-days"), do: dgettext("dashboard_tests", "since last week")
  defp trend_label("last-12-months"), do: dgettext("dashboard_tests", "since last year")
  defp trend_label("custom"), do: dgettext("dashboard_tests", "since last period")
  defp trend_label(_), do: dgettext("dashboard_tests", "since last month")

  defp environment_label("any"), do: dgettext("dashboard_tests", "Any")
  defp environment_label("local"), do: dgettext("dashboard_tests", "Local")
  defp environment_label("ci"), do: dgettext("dashboard_tests", "CI")
  defp environment_label(true), do: dgettext("dashboard_tests", "CI")
  defp environment_label(false), do: dgettext("dashboard_tests", "Local")

  defp opts_with_analytics_test_scheme(opts, "any"), do: opts
  defp opts_with_analytics_test_scheme(opts, scheme), do: Keyword.put(opts, :scheme, scheme)

  def test_scheme_label("any"), do: dgettext("dashboard_tests", "Any")
  def test_scheme_label(scheme), do: scheme

  defp with_test_run_tooltip_extra(scatter_data, group_by) do
    Map.update!(scatter_data, :series, fn series ->
      Enum.map(series, fn s ->
        %{
          name: scatter_name_label(s.name, group_by),
          data:
            Enum.map(s.data, fn point ->
              point
              |> Map.take([:value, :id])
              |> Map.put(:tooltipExtra, test_run_tooltip_extra(point.meta))
            end)
        }
      end)
    end)
  end

  defp with_selective_testing_tooltip_extra(scatter_data) do
    Map.update!(scatter_data, :series, fn series ->
      Enum.map(series, fn s ->
        %{
          name: environment_label(s.name),
          data:
            Enum.map(s.data, fn point ->
              point
              |> Map.take([:value, :id])
              |> Map.put(:tooltipExtra, selective_testing_tooltip_extra(point.meta))
            end)
        }
      end)
    end)
  end

  defp scatter_name_label(value, :environment), do: environment_label(value)
  defp scatter_name_label(value, _), do: scheme_value_label(value)

  defp test_run_tooltip_extra(meta) do
    [
      %{label: dgettext("dashboard_tests", "Scheme"), value: scheme_value_label(meta.scheme)},
      %{label: dgettext("dashboard_tests", "Status"), value: test_status_label(meta.status, meta.is_flaky)},
      %{label: dgettext("dashboard_tests", "Environment"), value: environment_label(meta.is_ci)}
    ]
  end

  defp selective_testing_tooltip_extra(meta) do
    [
      %{label: dgettext("dashboard_tests", "Environment"), value: environment_label(meta.is_ci)}
    ]
  end

  defp scheme_value_label(value) when value in ["", nil], do: dgettext("dashboard_tests", "Unknown")
  defp scheme_value_label(value), do: value

  defp test_status_label("success", true), do: dgettext("dashboard_tests", "Passed (flaky)")
  defp test_status_label("success", _), do: dgettext("dashboard_tests", "Passed")
  defp test_status_label("failure", _), do: dgettext("dashboard_tests", "Failed")
  defp test_status_label(status, _), do: String.capitalize(status)

  defp assign_test_run_duration_chart(socket, "scatter", group_by, opts) do
    project_id = socket.assigns.selected_project.id

    assign_async(socket, :test_run_duration_chart, fn ->
      data =
        project_id
        |> Analytics.test_run_duration_scatter_data(Keyword.put(opts, :group_by, group_by))
        |> with_test_run_tooltip_extra(group_by)

      {:ok, %{test_run_duration_chart: {:scatter, data}}}
    end)
  end

  defp assign_test_run_duration_chart(socket, _line, _group_by, _opts) do
    assign(socket, :test_run_duration_chart, AsyncResult.ok(:line))
  end

  defp assign_selective_testing_chart(socket, "scatter", opts) do
    assign_async(socket, :selective_testing_chart, fn ->
      data = opts |> BuildsAnalytics.selective_testing_scatter_data() |> with_selective_testing_tooltip_extra()
      {:ok, %{selective_testing_chart: {:scatter, data}}}
    end)
  end

  defp assign_selective_testing_chart(socket, _line, _opts) do
    assign(socket, :selective_testing_chart, AsyncResult.ok(:line))
  end

  defp duration_opts(%{
         analytics_period: {start_datetime, end_datetime},
         analytics_environment: env,
         analytics_test_scheme: scheme
       }) do
    [start_datetime: start_datetime, end_datetime: end_datetime]
    |> then(fn opts ->
      case env do
        "ci" -> Keyword.put(opts, :is_ci, true)
        "local" -> Keyword.put(opts, :is_ci, false)
        _ -> opts
      end
    end)
    |> opts_with_analytics_test_scheme(scheme)
  end

  defp selective_testing_opts(%{
         selected_project: project,
         selective_testing_period: {start_datetime, end_datetime},
         selective_testing_environment: env
       }) do
    opts = [project_id: project.id, start_datetime: start_datetime, end_datetime: end_datetime]

    case env do
      "ci" -> Keyword.put(opts, :is_ci, true)
      "local" -> Keyword.put(opts, :is_ci, false)
      _ -> opts
    end
  end

  defp duration_scatter_group_by_atom("environment"), do: :environment
  defp duration_scatter_group_by_atom(_), do: :scheme
end
