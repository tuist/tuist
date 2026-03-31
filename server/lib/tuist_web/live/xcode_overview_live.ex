defmodule TuistWeb.XcodeOverviewLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Previews.AppPreview

  alias Tuist.AppBuilds
  alias Tuist.Builds
  alias Tuist.Builds.Analytics, as: BuildsAnalytics
  alias Tuist.Bundles
  alias Tuist.Cache
  alias Tuist.Runs.Analytics, as: RunsAnalytics
  alias Tuist.Tests
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Utilities.Query

  def assign_mount(socket) do
    assign(socket, :user_agent, UAParser.parse(get_connect_info(socket, :user_agent)))
  end

  def assign_handle_params(socket, params, uri_path) do
    uri = URI.new!("?" <> URI.encode_query(params))
    project = socket.assigns.selected_project

    %{preset: analytics_preset, period: analytics_period} =
      DatePicker.date_picker_params(params, "analytics")

    analytics_environment = params["analytics-environment"] || "any"

    %{preset: builds_preset, period: builds_period} =
      DatePicker.date_picker_params(params, "builds")

    builds_environment = params["builds-environment"] || "any"

    %{preset: bundle_size_preset, period: bundle_size_period} =
      DatePicker.date_picker_params(params, "bundle-size")

    bundle_size_selected_app = params["bundle-size-app"] || Bundles.default_app(project)

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
      builds_environment_label: environment_label(builds_environment),
      bundle_size_preset: bundle_size_preset,
      bundle_size_period: bundle_size_period,
      bundle_size_selected_app: bundle_size_selected_app
    )
    |> assign_async(:binary_cache_hit_rate_analytics, fn ->
      {:ok, %{binary_cache_hit_rate_analytics: Cache.Analytics.cache_hit_rate_analytics(analytics_opts)}}
    end)
    |> assign_async(:selective_testing_analytics, fn ->
      {:ok, %{selective_testing_analytics: BuildsAnalytics.selective_testing_analytics(analytics_opts)}}
    end)
    |> assign_async(:build_analytics, fn ->
      {:ok, %{build_analytics: BuildsAnalytics.build_duration_analytics(project.id, analytics_opts)}}
    end)
    |> assign_async(:test_analytics, fn ->
      {:ok, %{test_analytics: RunsAnalytics.runs_duration_analytics("test", analytics_opts)}}
    end)
    |> assign_async(:build_time_analytics, fn ->
      {:ok, %{build_time_analytics: BuildsAnalytics.build_time_analytics(analytics_opts)}}
    end)
    |> assign_async([:recent_test_runs, :failed_test_runs_count, :passed_test_runs_count], fn ->
      fetch_test_runs_data(project)
    end)
    |> assign_async(:latest_app_previews, fn ->
      {:ok, %{latest_app_previews: AppBuilds.latest_previews_with_distinct_bundle_ids(project)}}
    end)
    |> assign_async(:recent_build_runs, fn ->
      fetch_recent_build_runs_data(project)
    end)
    |> assign_async([:passed_build_runs_count, :failed_build_runs_count], fn ->
      fetch_recent_build_status_counts(project.id)
    end)
    |> assign_async(:builds_duration_analytics, fn ->
      {:ok, %{builds_duration_analytics: BuildsAnalytics.build_duration_analytics(project.id, builds_opts)}}
    end)
    |> assign_async(
      [:bundle_size_apps, :bundle_size_analytics],
      fn -> fetch_bundles_data(project, bundle_size_period) end
    )
  end

  defp fetch_test_runs_data(project) do
    {recent_test_runs, _meta} =
      Tests.list_test_runs(%{
        last: 40,
        filters: [
          %{field: :project_id, op: :==, value: project.id},
          %{field: :status, op: :!=, value: "in_progress"}
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

    failed_test_runs_count = Enum.count(recent_test_runs, fn run -> run.status == "failure" end)

    passed_test_runs_count =
      Enum.count(recent_test_runs, fn run -> run.status == "success" end)

    {:ok,
     %{
       recent_test_runs: recent_test_runs_chart_data,
       failed_test_runs_count: failed_test_runs_count,
       passed_test_runs_count: passed_test_runs_count
     }}
  end

  defp fetch_recent_build_runs_data(project) do
    {recent_build_runs, _meta} =
      Builds.list_build_runs(%{
        last: 30,
        filters: [
          %{field: :project_id, op: :==, value: project.id},
          %{field: :status, op: :!=, value: "processing"},
          %{field: :status, op: :!=, value: "failed_processing"}
        ],
        order_by: [:inserted_at],
        order_directions: [:asc]
      })

    {:ok, %{recent_build_runs: recent_build_runs_chart_data(recent_build_runs, project)}}
  end

  defp fetch_recent_build_status_counts(project_id) do
    %{successful_count: passed_build_runs_count, failed_count: failed_build_runs_count} =
      Builds.recent_build_status_counts(project_id, limit: 30)

    {:ok, %{passed_build_runs_count: passed_build_runs_count, failed_build_runs_count: failed_build_runs_count}}
  end

  defp build_opts(project_id, {start_datetime, end_datetime}, environment) do
    opts = [project_id: project_id, start_datetime: start_datetime, end_datetime: end_datetime]

    case environment do
      "ci" -> Keyword.put(opts, :is_ci, true)
      "local" -> Keyword.put(opts, :is_ci, false)
      _ -> opts
    end
  end

  defp fetch_bundles_data(project, {start_datetime, end_datetime}) do
    opts = [project_id: project.id, start_datetime: start_datetime, end_datetime: end_datetime]

    bundle_size_apps = Bundles.distinct_project_app_bundles(project)

    bundle_size_analytics =
      project
      |> Bundles.project_bundle_install_size_analytics(opts)
      |> Enum.map(
        &[
          &1.date,
          &1.bundle_install_size
        ]
      )

    {:ok,
     %{
       bundle_size_apps: Enum.map(bundle_size_apps, & &1.name),
       bundle_size_analytics: bundle_size_analytics
     }}
  end

  defp recent_build_runs_chart_data(recent_build_runs, project) do
    Enum.map(recent_build_runs, fn run ->
      color =
        case run.status do
          "success" -> "var:noora-chart-primary"
          "failure" -> "var:noora-chart-destructive"
        end

      value = (run.duration / 1000) |> Decimal.from_float() |> Decimal.round(0)

      %{
        value: value,
        itemStyle: %{color: color},
        date: run.inserted_at,
        url: ~p"/#{project.account.name}/#{project.name}/builds/build-runs/#{run.id}"
      }
    end)
  end

  defp analytics_trend_label("last-24-hours"), do: dgettext("dashboard_projects", "since yesterday")
  defp analytics_trend_label("last-7-days"), do: dgettext("dashboard_projects", "since last week")
  defp analytics_trend_label("last-12-months"), do: dgettext("dashboard_projects", "since last year")
  defp analytics_trend_label("custom"), do: dgettext("dashboard_projects", "since last period")
  defp analytics_trend_label(_), do: dgettext("dashboard_projects", "since last month")

  defp environment_label("any"), do: dgettext("dashboard_projects", "Any")
  defp environment_label("local"), do: dgettext("dashboard_projects", "Local")
  defp environment_label("ci"), do: dgettext("dashboard_projects", "CI")
end
