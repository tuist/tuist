defmodule TuistWeb.GradleBuildsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.PercentileDropdownWidget
  import TuistWeb.Runs.RanByBadge

  alias Tuist.Gradle
  alias Tuist.Gradle.Analytics
  alias Tuist.Repo
  alias Tuist.Tasks
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Utilities.Query

  @recent_builds_page_size 40

  def assign_handle_params(socket, params) do
    socket
    |> assign(:current_params, params)
    |> assign_analytics(params)
    |> assign_recent_builds()
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

    uri = URI.new!("?" <> URI.encode_query(params))

    [
      builds_duration_analytics,
      builds_p99_durations,
      builds_p90_durations,
      builds_p50_durations,
      total_builds_analytics,
      failed_builds_analytics,
      build_success_rate_analytics
    ] =
      Tasks.parallel_tasks([
        fn -> Analytics.build_duration_analytics(project.id, opts) end,
        fn -> Analytics.build_percentile_durations(project.id, 0.99, opts) end,
        fn -> Analytics.build_percentile_durations(project.id, 0.9, opts) end,
        fn -> Analytics.build_percentile_durations(project.id, 0.5, opts) end,
        fn -> Analytics.build_analytics(project.id, opts) end,
        fn -> Analytics.build_analytics(project.id, Keyword.put(opts, :status, "failure")) end,
        fn -> Analytics.build_success_rate_analytics(project.id, opts) end
      ])

    analytics_selected_widget = params["analytics-selected-widget"] || "build-duration"

    socket
    |> assign(:analytics_preset, preset)
    |> assign(:analytics_period, period)
    |> assign(:analytics_trend_label, analytics_trend_label(preset))
    |> assign(:analytics_selected_widget, analytics_selected_widget)
    |> assign(:analytics_environment, analytics_environment)
    |> assign(:analytics_environment_label, environment_label(analytics_environment))
    |> assign(:builds_duration_analytics, builds_duration_analytics)
    |> assign(:builds_p99_durations, builds_p99_durations)
    |> assign(:builds_p90_durations, builds_p90_durations)
    |> assign(:builds_p50_durations, builds_p50_durations)
    |> assign(:total_builds_analytics, total_builds_analytics)
    |> assign(:failed_builds_analytics, failed_builds_analytics)
    |> assign(:build_success_rate_analytics, build_success_rate_analytics)
    |> assign(:selected_build_duration_type, params["build-duration-type"] || "avg")
    |> assign(:uri, uri)
  end

  defp environment_label("any"), do: dgettext("dashboard_gradle", "Any")
  defp environment_label("local"), do: dgettext("dashboard_gradle", "Local")
  defp environment_label("ci"), do: dgettext("dashboard_gradle", "CI")

  defp analytics_trend_label("last-24-hours"), do: dgettext("dashboard_gradle", "since yesterday")
  defp analytics_trend_label("last-7-days"), do: dgettext("dashboard_gradle", "since last week")
  defp analytics_trend_label("last-12-months"), do: dgettext("dashboard_gradle", "since last year")
  defp analytics_trend_label("custom"), do: dgettext("dashboard_gradle", "since last period")
  defp analytics_trend_label(_), do: dgettext("dashboard_gradle", "since last month")

  def assign_configuration_insights_options(%{assigns: %{selected_project: project}} = socket, params) do
    configuration_insights_type = params["configuration-insights-type"] || "gradle-version"

    %{preset: preset, period: {start_datetime, end_datetime} = period} =
      DatePicker.date_picker_params(params, "configuration-insights")

    opts = [start_datetime: start_datetime, end_datetime: end_datetime]

    socket =
      socket
      |> assign(:configuration_insights_type, configuration_insights_type)
      |> assign(:configuration_insights_preset, preset)
      |> assign(:configuration_insights_period, period)

    configuration_insights_analytics =
      Analytics.build_duration_analytics_by_category(
        project.id,
        case configuration_insights_type do
          "java-version" -> :java_version
          _ -> :gradle_version
        end,
        opts
      )

    socket
    |> assign(
      :configuration_insights_chart_height,
      (configuration_insights_analytics |> Enum.map(& &1.category) |> Enum.count()) * 28
    )
    |> assign(:next_configuration_insights_analytics, configuration_insights_analytics)
  end

  def assign_initial_configuration_insights(
        %{assigns: %{next_configuration_insights_analytics: next_configuration_insights_analytics}} = socket
      ) do
    socket
    |> assign(
      :configuration_insights_analytics,
      next_configuration_insights_analytics
    )
    |> assign(
      :configuration_insights_chart_height,
      (next_configuration_insights_analytics |> Enum.map(& &1.category) |> Enum.count()) * 28
    )
  end

  def assign_configuration_insights(socket) do
    Process.send_after(self(), :update_configuration_insights, 0)

    push_event(socket, "resize", %{})
  end

  def configuration_insights_label("java-version"), do: dgettext("dashboard_gradle", "Java version")
  def configuration_insights_label(_), do: dgettext("dashboard_gradle", "Gradle version")

  defp assign_recent_builds(%{assigns: %{selected_project: project}} = socket) do
    {builds, _meta} = Gradle.list_builds(project.id, %{page_size: @recent_builds_page_size})
    builds = Repo.preload(builds, :built_by_account)

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
          date: build.inserted_at
        }
      end)

    successful_builds_count = Enum.count(builds, &(&1.status == "success"))
    failed_builds_count = Enum.count(builds, &(&1.status == "failure"))

    socket
    |> assign(:builds, builds)
    |> assign(:recent_builds_chart_data, recent_builds_chart_data)
    |> assign(:successful_builds_count, successful_builds_count)
    |> assign(:failed_builds_count, failed_builds_count)
  end
end
