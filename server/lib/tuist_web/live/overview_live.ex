defmodule TuistWeb.OverviewLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Previews.AppPreview

  alias Tuist.Bundles
  alias Tuist.CommandEvents
  alias Tuist.Runs
  alias Tuist.Runs.Analytics
  alias TuistWeb.Utilities.Query

  def mount(
        _params,
        _session,
        %{assigns: %{selected_project: project, selected_account: account}} = socket
      ) do
    {:ok,
     socket
     |> assign(
       :user_agent,
       UAParser.parse(get_connect_info(socket, :user_agent))
     )
     |> assign(
       :head_title,
       "#{gettext("Overview")} · #{account.name}/#{project.name} · Tuist"
     )}
  end

  def handle_params(params, _uri, %{assigns: %{selected_project: _project}} = socket) do
    uri =
      URI.new!(
        "?" <>
          (params
           |> Map.take([
             "analytics_environment",
             "analytics_date_range",
             "builds_environment",
             "builds_date_range"
           ])
           |> URI.encode_query())
      )

    {
      :noreply,
      socket
      |> assign_analytics(params)
      |> assign_builds(params)
      |> assign_bundles(params)
      |> assign(
        :uri,
        uri
      )
    }
  end

  defp assign_test_runs_analytics(%{assigns: %{selected_project: project}} = socket) do
    {recent_test_runs, _meta} =
      CommandEvents.list_test_runs(%{
        last: 40,
        filters: [
          %{field: :project_id, op: :==, value: project.id}
        ],
        order_by: [:created_at],
        order_directions: [:asc]
      })

    recent_test_runs_chart_data =
      Enum.map(recent_test_runs, fn run ->
        color =
          case run.status do
            :success -> "var:noora-chart-primary"
            :failure -> "var:noora-chart-destructive"
          end

        value = (run.duration / 1000) |> Decimal.from_float() |> Decimal.round(0)

        %{value: value, itemStyle: %{color: color}, date: run.created_at}
      end)

    failed_test_runs_count = Enum.count(recent_test_runs, fn run -> run.status == :failure end)

    passed_test_runs_count =
      Enum.count(recent_test_runs, fn run -> run.status == :success end)

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
    bundle_size_date_range = params["bundle-size-date-range"] || "last-30-days"

    bundle_size_analytics =
      project
      |> Bundles.project_bundle_install_size_analytics(
        project_id: project.id,
        start_date: start_date(bundle_size_date_range)
      )
      |> Enum.map(
        &[
          &1.date,
          &1.bundle_install_size
        ]
      )

    socket
    |> assign(:bundle_size_selected_app, bundle_size_selected_app)
    |> assign(:bundle_size_apps, Enum.map(bundle_size_apps, & &1.name))
    |> assign(
      :bundle_size_date_range,
      bundle_size_date_range
    )
    |> assign(:bundle_size_analytics, bundle_size_analytics)
  end

  defp assign_builds(%{assigns: %{selected_project: project}} = socket, params) do
    builds_date_range = params["builds_date_range"] || "last_30_days"

    start_date =
      case builds_date_range do
        "last_12_months" -> Date.add(DateTime.utc_now(), -365)
        "last_30_days" -> Date.add(DateTime.utc_now(), -30)
        "last_7_days" -> Date.add(DateTime.utc_now(), -7)
      end

    builds_environment = params["builds_environment"] || "any"

    opts = [
      project_id: project.id,
      start_date: start_date
    ]

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
      Runs.recent_build_status_counts(project.id, limit: 30, order: :asc)

    socket
    |> assign(
      :builds_date_range,
      builds_date_range
    )
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
    date_range = date_range(params)

    start_date =
      case date_range do
        "last_12_months" -> Date.add(DateTime.utc_now(), -365)
        "last_30_days" -> Date.add(DateTime.utc_now(), -30)
        "last_7_days" -> Date.add(DateTime.utc_now(), -7)
      end

    analytics_environment = analytics_environment(params)

    opts = [
      project_id: project.id,
      start_date: start_date
    ]

    opts =
      case analytics_environment do
        "ci" -> Keyword.put(opts, :is_ci, true)
        "local" -> Keyword.put(opts, :is_ci, false)
        _ -> opts
      end

    socket
    |> assign(
      :analytics_date_range,
      date_range
    )
    |> assign(
      :analytics_trend_label,
      analytics_trend_label(date_range)
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
      analytics_tasks = [
        Task.async(fn -> Analytics.cache_hit_rate_analytics(opts) end),
        Task.async(fn -> Analytics.selective_testing_analytics(opts) end),
        Task.async(fn -> Analytics.build_duration_analytics(project.id, opts) end),
        Task.async(fn -> Analytics.runs_duration_analytics("test", opts) end)
      ]

      [
        binary_cache_hit_rate_analytics,
        selective_testing_analytics,
        build_analytics,
        test_analytics
      ] = Task.await_many(analytics_tasks, 10_000)

      socket
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

  defp analytics_trend_label("last_7_days"), do: gettext("since last week")
  defp analytics_trend_label("last_12_months"), do: gettext("since last year")
  defp analytics_trend_label(_), do: gettext("since last month")

  defp environment_label("any") do
    gettext("Any")
  end

  defp environment_label("local") do
    gettext("Local")
  end

  defp environment_label("ci") do
    gettext("CI")
  end

  defp date_range(params) do
    analytics_date_range = params["analytics_date_range"]

    if is_nil(analytics_date_range) do
      "last_30_days"
    else
      analytics_date_range
    end
  end

  defp analytics_environment(params) do
    analytics_environment = params["analytics_environment"]

    if is_nil(analytics_environment) do
      "any"
    else
      analytics_environment
    end
  end

  defp start_date("last-12-months"), do: Date.add(DateTime.utc_now(), -365)
  defp start_date("last-30-days"), do: Date.add(DateTime.utc_now(), -30)
  defp start_date("last-7-days"), do: Date.add(DateTime.utc_now(), -7)
end
