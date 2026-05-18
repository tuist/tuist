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
    project = socket.assigns.selected_project

    %{preset: analytics_preset, period: analytics_period} =
      DatePicker.date_picker_params(params, "analytics")

    analytics_environment = params["analytics-environment"] || "any"

    %{preset: builds_preset, period: builds_period} =
      DatePicker.date_picker_params(params, "builds")

    builds_environment = params["builds-environment"] || "any"
    analytics_opts = build_opts(project.id, analytics_period, analytics_environment)
    builds_opts = build_opts(project.id, builds_period, builds_environment)

    socket
    |> assign(
      uri: uri,
      uri_path: uri_path,
      analytics_preset: analytics_preset,
      analytics_period: analytics_period,
      analytics_trend_label: analytics_trend_label(analytics_preset),
      analytics_environment: analytics_environment,
      analytics_environment_label: environment_label(analytics_environment),
      builds_preset: builds_preset,
      builds_period: builds_period,
      builds_environment: builds_environment,
      builds_environment_label: builds_environment_label(builds_environment)
    )
    |> assign_async(:cache_hit_rate_analytics, fn ->
      {:ok, %{cache_hit_rate_analytics: GradleAnalytics.cache_hit_rate_analytics(project.id, analytics_opts)}}
    end)
    |> assign_async(:build_duration_analytics, fn ->
      {:ok, %{build_duration_analytics: GradleAnalytics.build_duration_analytics(project.id, analytics_opts)}}
    end)
    |> assign_async(:test_duration_analytics, fn ->
      {:ok, %{test_duration_analytics: TestsAnalytics.test_run_duration_analytics(project.id, analytics_opts)}}
    end)
    |> assign_async(
      [:recent_test_runs, :failed_test_runs_count, :passed_test_runs_count],
      fn -> fetch_test_runs_data(project) end
    )
    |> assign_async(
      [:recent_build_runs, :successful_builds_count, :failed_builds_count],
      fn -> fetch_build_runs_data(project) end
    )
    |> assign_async(:builds_duration_analytics, fn ->
      {:ok, %{builds_duration_analytics: GradleAnalytics.build_duration_analytics(project.id, builds_opts)}}
    end)
  end

  defp build_opts(project_id, {start_datetime, end_datetime}, environment) do
    opts = [
      project_id: project_id,
      start_datetime: start_datetime,
      end_datetime: end_datetime
    ]

    case environment do
      "ci" -> Keyword.put(opts, :is_ci, true)
      "local" -> Keyword.put(opts, :is_ci, false)
      _ -> opts
    end
  end

  defp fetch_test_runs_data(project) do
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

        %{
          value: value,
          itemStyle: %{color: color},
          date: run.ran_at,
          url: ~p"/#{project.account.name}/#{project.name}/tests/test-runs/#{run.id}"
        }
      end)

    failed_test_runs_count = Enum.count(recent_test_runs, &(&1.status == "failure"))
    passed_test_runs_count = Enum.count(recent_test_runs, &(&1.status == "success"))

    {:ok,
     %{
       recent_test_runs: recent_test_runs_chart_data,
       failed_test_runs_count: failed_test_runs_count,
       passed_test_runs_count: passed_test_runs_count
     }}
  end

  defp fetch_build_runs_data(project) do
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

        %{
          value: build.duration_ms,
          itemStyle: %{color: color},
          date: build.inserted_at,
          url: ~p"/#{project.account.name}/#{project.name}/builds/build-runs/#{build.id}"
        }
      end)

    successful_builds_count = Enum.count(builds, &(&1.status == "success"))
    failed_builds_count = Enum.count(builds, &(&1.status == "failure"))

    {:ok,
     %{
       recent_build_runs: recent_builds_chart_data,
       successful_builds_count: successful_builds_count,
       failed_builds_count: failed_builds_count
     }}
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
end
