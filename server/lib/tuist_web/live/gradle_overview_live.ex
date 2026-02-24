defmodule TuistWeb.GradleOverviewLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection

  alias Tuist.Gradle
  alias Tuist.Gradle.Analytics, as: GradleAnalytics
  alias Tuist.Tests
  alias Tuist.Tests.Analytics, as: TestsAnalytics
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Utilities.Query

  @doc """
  Assigns gradle-specific handle_params data to the socket.
  Called from OverviewLive when the project is a gradle project.
  """
  def assign_handle_params(socket, params, uri_path) do
    uri = URI.new!("?" <> URI.encode_query(params))

    socket
    |> assign_analytics(params)
    |> assign_builds(params)
    |> assign_test_runs()
    |> assign(:uri, uri)
    |> assign(:uri_path, uri_path)
  end

  defp assign_analytics(%{assigns: %{selected_project: project}} = socket, params) do
    %{preset: preset, period: {start_datetime, end_datetime} = period} =
      DatePicker.date_picker_params(params, "analytics")

    analytics_environment = params["analytics-environment"] || "any"

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

    [cache_hit_rate_analytics, build_duration_analytics, test_duration_analytics] =
      combined_overview_analytics(project.id, opts)

    socket
    |> assign(:analytics_preset, preset)
    |> assign(:analytics_period, period)
    |> assign(:analytics_trend_label, analytics_trend_label(preset))
    |> assign(:analytics_environment, analytics_environment)
    |> assign(:analytics_environment_label, environment_label(analytics_environment))
    |> assign(
      :cache_hit_rate,
      cache_hit_rate_analytics.avg_hit_rate |> Decimal.from_float() |> Decimal.round(1)
    )
    |> assign(:cache_hit_rate_analytics, cache_hit_rate_analytics)
    |> assign(:build_duration_analytics, build_duration_analytics)
    |> assign(:test_duration_analytics, test_duration_analytics)
  end

  defp assign_builds(%{assigns: %{selected_project: project}} = socket, params) do
    %{preset: preset, period: {start_datetime, end_datetime} = period} =
      DatePicker.date_picker_params(params, "builds")

    builds_environment = params["builds-environment"] || "any"

    opts = [
      project_id: project.id,
      start_datetime: start_datetime,
      end_datetime: end_datetime
    ]

    opts =
      case builds_environment do
        "ci" -> Keyword.put(opts, :is_ci, true)
        "local" -> Keyword.put(opts, :is_ci, false)
        _ -> opts
      end

    {builds, _meta} = Gradle.list_builds(project.id, %{page_size: 30})

    recent_builds_chart_data =
      builds
      |> Enum.reverse()
      |> Enum.map(fn build ->
        color =
          case build.status do
            "success" -> "var:noora-chart-primary"
            "failure" -> "var:noora-chart-destructive"
            _ -> "var:noora-chart-warning"
          end

        %{value: build.duration_ms, itemStyle: %{color: color}, date: build.inserted_at}
      end)

    successful_builds_count = Enum.count(builds, &(&1.status == "success"))
    failed_builds_count = Enum.count(builds, &(&1.status == "failure"))

    builds_duration_analytics = GradleAnalytics.build_duration_analytics(project.id, opts)

    socket
    |> assign(:builds_preset, preset)
    |> assign(:builds_period, period)
    |> assign(:builds_environment, builds_environment)
    |> assign(:builds_environment_label, builds_environment_label(builds_environment))
    |> assign(:recent_build_runs, recent_builds_chart_data)
    |> assign(:successful_builds_count, successful_builds_count)
    |> assign(:failed_builds_count, failed_builds_count)
    |> assign(:builds_duration_analytics, builds_duration_analytics)
  end

  defp assign_test_runs(%{assigns: %{selected_project: project}} = socket) do
    {recent_test_runs, _meta} =
      Tests.list_test_runs(%{
        last: 40,
        filters: [
          %{field: :project_id, op: :==, value: project.id},
          %{field: :build_system, op: :==, value: "gradle"}
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

    failed_test_runs_count = Enum.count(recent_test_runs, &(&1.status == "failure"))
    passed_test_runs_count = Enum.count(recent_test_runs, &(&1.status == "success"))

    socket
    |> assign(:recent_test_runs, recent_test_runs_chart_data)
    |> assign(:failed_test_runs_count, failed_test_runs_count)
    |> assign(:passed_test_runs_count, passed_test_runs_count)
  end

  defp analytics_trend_label("last-24-hours"), do: dgettext("dashboard_gradle", "since yesterday")
  defp analytics_trend_label("last-7-days"), do: dgettext("dashboard_gradle", "since last week")
  defp analytics_trend_label("last-12-months"), do: dgettext("dashboard_gradle", "since last year")
  defp analytics_trend_label("custom"), do: dgettext("dashboard_gradle", "since last period")
  defp analytics_trend_label(_), do: dgettext("dashboard_gradle", "since last month")

  defp environment_label("any"), do: dgettext("dashboard_gradle", "Any")
  defp environment_label("local"), do: dgettext("dashboard_gradle", "Local")
  defp environment_label("ci"), do: dgettext("dashboard_gradle", "CI")

  defp builds_environment_label("any"), do: dgettext("dashboard_gradle", "Any")
  defp builds_environment_label("local"), do: dgettext("dashboard_gradle", "Local")
  defp builds_environment_label("ci"), do: dgettext("dashboard_gradle", "CI")

  defp combined_overview_analytics(project_id, opts) do
    queries = [
      fn -> GradleAnalytics.cache_hit_rate_analytics(project_id, opts) end,
      fn -> GradleAnalytics.build_duration_analytics(project_id, opts) end,
      fn -> TestsAnalytics.test_run_duration_analytics(project_id, opts) end
    ]

    Tuist.Tasks.parallel_tasks(queries)
  end
end
