defmodule TuistWeb.OverviewLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Previews.AppPreview

  alias Tuist.Bundles
  alias Tuist.Cache
  alias Tuist.Runs
  alias Tuist.Runs.Analytics
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Utilities.Query

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    {:ok,
     socket
     |> assign(
       :user_agent,
       UAParser.parse(get_connect_info(socket, :user_agent))
     )
     |> assign(
       :head_title,
       "#{dgettext("dashboard_projects", "Overview")} · #{account.name}/#{project.name} · Tuist"
     )}
  end

  def handle_event(
        "analytics_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        socket
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

    {:noreply, push_patch(socket, to: "#{socket.assigns.uri_path}?#{query_params}")}
  end

  def handle_event(
        "bundle_size_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        socket
      ) do
    query_params =
      if preset == "custom" do
        socket.assigns.uri.query
        |> Query.put("bundle-size-date-range", "custom")
        |> Query.put("bundle-size-start-date", start_date)
        |> Query.put("bundle-size-end-date", end_date)
      else
        Query.put(socket.assigns.uri.query, "bundle-size-date-range", preset)
      end

    {:noreply, push_patch(socket, to: "#{socket.assigns.uri_path}?#{query_params}")}
  end

  def handle_event(
        "builds_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        socket
      ) do
    query_params =
      if preset == "custom" do
        socket.assigns.uri.query
        |> Query.put("builds-date-range", "custom")
        |> Query.put("builds-start-date", start_date)
        |> Query.put("builds-end-date", end_date)
      else
        Query.put(socket.assigns.uri.query, "builds-date-range", preset)
      end

    {:noreply, push_patch(socket, to: "#{socket.assigns.uri_path}?#{query_params}")}
  end

  def handle_params(params, request_uri, %{assigns: %{selected_project: _project}} = socket) do
    full_uri = URI.parse(request_uri)

    uri =
      URI.new!(
        "?" <>
          (params
           |> Map.take([
             "analytics-environment",
             "analytics-date-range",
             "analytics-start-date",
             "analytics-end-date",
             "builds-environment",
             "builds-date-range",
             "builds-start-date",
             "builds-end-date",
             "bundle-size-date-range",
             "bundle-size-start-date",
             "bundle-size-end-date",
             "bundle-size-app"
           ])
           |> URI.encode_query())
      )

    {
      :noreply,
      socket
      |> assign_analytics(params)
      |> assign_builds(params)
      |> assign_bundles(params)
      |> assign(:uri, uri)
      |> assign(:uri_path, full_uri.path)
    }
  end

  defp assign_test_runs_analytics(%{assigns: %{selected_project: project}} = socket) do
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

    passed_test_runs_count =
      Enum.count(recent_test_runs, fn run -> run.status == "success" end)

    socket
    |> assign(
      :recent_test_runs,
      recent_test_runs_chart_data
    )
    |> assign(
      :failed_test_runs_count,
      failed_test_runs_count
    )
    |> assign(
      :passed_test_runs_count,
      passed_test_runs_count
    )
  end

  defp assign_bundles(%{assigns: %{selected_project: project}} = socket, params) do
    bundle_size_apps = Bundles.distinct_project_app_bundles(project)
    bundle_size_selected_app = params["bundle-size-app"] || Bundles.default_app(project)

    %{preset: preset, period: {start_datetime, end_datetime} = period} =
      DatePicker.date_picker_params(params, "bundle-size")

    opts = [project_id: project.id, start_datetime: start_datetime, end_datetime: end_datetime]

    bundle_size_analytics =
      project
      |> Bundles.project_bundle_install_size_analytics(opts)
      |> Enum.map(
        &[
          &1.date,
          &1.bundle_install_size
        ]
      )

    socket
    |> assign(:bundle_size_selected_app, bundle_size_selected_app)
    |> assign(:bundle_size_apps, Enum.map(bundle_size_apps, & &1.name))
    |> assign(:bundle_size_preset, preset)
    |> assign(:bundle_size_period, period)
    |> assign(:bundle_size_analytics, bundle_size_analytics)
  end

  defp assign_builds(%{assigns: %{selected_project: project}} = socket, params) do
    %{preset: preset, period: {start_datetime, end_datetime} = period} =
      DatePicker.date_picker_params(params, "builds")

    builds_environment = params["builds-environment"] || "any"

    opts = [project_id: project.id, start_datetime: start_datetime, end_datetime: end_datetime]

    opts =
      case builds_environment do
        "ci" -> Keyword.put(opts, :is_ci, true)
        "local" -> Keyword.put(opts, :is_ci, false)
        _ -> opts
      end

    {recent_build_runs, _meta} =
      Runs.list_build_runs(%{
        last: 30,
        filters: [
          %{field: :project_id, op: :==, value: project.id}
        ],
        order_by: [:inserted_at],
        order_directions: [:asc]
      })

    recent_build_runs_chart_data = recent_build_runs_chart_data(recent_build_runs)

    %{successful_count: passed_build_runs_count, failed_count: failed_build_runs_count} =
      Runs.recent_build_status_counts(project.id, limit: 30)

    socket
    |> assign(:builds_preset, preset)
    |> assign(:builds_period, period)
    |> assign(
      :builds_environment,
      builds_environment
    )
    |> assign(
      :builds_environment_label,
      environment_label(builds_environment)
    )
    |> assign(
      :recent_build_runs,
      recent_build_runs_chart_data
    )
    |> assign(
      :failed_build_runs_count,
      failed_build_runs_count
    )
    |> assign(
      :passed_build_runs_count,
      passed_build_runs_count
    )
    |> assign(
      :builds_duration_analytics,
      Analytics.build_duration_analytics(project.id, opts)
    )
  end

  defp recent_build_runs_chart_data(recent_build_runs) do
    Enum.map(recent_build_runs, fn run ->
      color =
        case run.status do
          :success -> "var:noora-chart-primary"
          :failure -> "var:noora-chart-destructive"
        end

      value = (run.duration / 1000) |> Decimal.from_float() |> Decimal.round(0)

      %{value: value, itemStyle: %{color: color}, date: run.inserted_at}
    end)
  end

  defp assign_analytics(%{assigns: %{selected_project: project}} = socket, params) do
    %{preset: preset, period: {start_datetime, end_datetime} = period} =
      DatePicker.date_picker_params(params, "analytics")

    analytics_environment = params["analytics-environment"] || "any"

    opts = [project_id: project.id, start_datetime: start_datetime, end_datetime: end_datetime]

    opts =
      case analytics_environment do
        "ci" -> Keyword.put(opts, :is_ci, true)
        "local" -> Keyword.put(opts, :is_ci, false)
        _ -> opts
      end

    socket
    |> assign(:analytics_preset, preset)
    |> assign(:analytics_period, period)
    |> assign(
      :analytics_trend_label,
      analytics_trend_label(preset)
    )
    |> assign(
      :analytics_environment,
      analytics_environment
    )
    |> assign(
      :analytics_environment_label,
      environment_label(analytics_environment)
    )
    |> then(fn socket ->
      [
        binary_cache_hit_rate_analytics,
        selective_testing_analytics,
        build_analytics,
        test_analytics
      ] = combined_overview_analytics(project.id, opts)

      socket
      |> assign(
        :build_time_analytics,
        Analytics.build_time_analytics(opts)
      )
      |> assign(:binary_cache_hit_rate_analytics, binary_cache_hit_rate_analytics)
      |> assign(:selective_testing_analytics, selective_testing_analytics)
      |> assign(:build_analytics, build_analytics)
      |> assign(:test_analytics, test_analytics)
    end)
    |> assign_test_runs_analytics()
    |> assign(
      :latest_app_previews,
      Tuist.AppBuilds.latest_previews_with_distinct_bundle_ids(project)
    )
  end

  defp analytics_trend_label("last-24-hours"), do: dgettext("dashboard_projects", "since yesterday")
  defp analytics_trend_label("last-7-days"), do: dgettext("dashboard_projects", "since last week")
  defp analytics_trend_label("last-12-months"), do: dgettext("dashboard_projects", "since last year")
  defp analytics_trend_label("custom"), do: dgettext("dashboard_projects", "since last period")
  defp analytics_trend_label(_), do: dgettext("dashboard_projects", "since last month")

  defp environment_label("any") do
    dgettext("dashboard_projects", "Any")
  end

  defp environment_label("local") do
    dgettext("dashboard_projects", "Local")
  end

  defp environment_label("ci") do
    dgettext("dashboard_projects", "CI")
  end

  defp combined_overview_analytics(project_id, opts) do
    queries = [
      fn -> Cache.Analytics.cache_hit_rate_analytics(opts) end,
      fn -> Analytics.selective_testing_analytics(opts) end,
      fn -> Analytics.build_duration_analytics(project_id, opts) end,
      fn -> Analytics.runs_duration_analytics("test", opts) end
    ]

    Tuist.Tasks.parallel_tasks(queries)
  end
end
