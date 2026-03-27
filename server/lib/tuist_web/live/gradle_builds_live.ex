defmodule TuistWeb.GradleBuildsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.Skeleton
  import TuistWeb.PercentileDropdownWidget
  import TuistWeb.Runs.RanByBadge

  alias Tuist.Gradle
  alias Tuist.Gradle.Analytics
  alias Tuist.Repo
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Utilities.Query

  @recent_builds_page_size 40

  def assign_handle_params(socket, params) do
    socket
    |> assign(:current_params, params)
    |> assign_analytics(params)
    |> assign_recent_builds()
  end

  def handle_info({:gradle_build_created, _build}, socket) do
    if Query.has_pagination_params?(socket.assigns.uri.query) do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign_handle_params(socket.assigns.current_params)
       |> assign_configuration_insights_options(socket.assigns.current_params)
       |> assign_initial_configuration_insights()}
    end
  end

  def handle_info(_event, socket), do: {:noreply, socket}

  def handle_event("select_widget", %{"widget" => widget}, socket) do
    query = Query.put(socket.assigns.uri.query, "analytics-selected-widget", widget)
    uri = URI.new!("?" <> query)

    socket =
      socket
      |> assign(:analytics_selected_widget, widget)
      |> assign(:uri, uri)
      |> push_event("replace-url", %{url: "?" <> query})

    if socket.assigns.total_builds_analytics.ok? do
      chart_data =
        analytics_chart_data(
          widget,
          socket.assigns.total_builds_analytics.result,
          socket.assigns.failed_builds_analytics.result,
          socket.assigns.build_success_rate_analytics.result
        )

      {:noreply, assign(socket, :analytics_chart_data, %{socket.assigns.analytics_chart_data | result: chart_data})}
    else
      {:noreply, socket}
    end
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

    analytics_selected_widget = params["analytics-selected-widget"] || "build-duration"

    socket
    |> assign(:analytics_preset, preset)
    |> assign(:analytics_period, period)
    |> assign(:analytics_trend_label, analytics_trend_label(preset))
    |> assign(:analytics_selected_widget, analytics_selected_widget)
    |> assign(:analytics_environment, analytics_environment)
    |> assign(:analytics_environment_label, environment_label(analytics_environment))
    |> assign(:selected_build_duration_type, params["build-duration-type"] || "avg")
    |> assign(:uri, uri)
    |> assign_async(
      [:builds_duration_analytics, :builds_p99_durations, :builds_p90_durations, :builds_p50_durations],
      fn ->
        {:ok,
         %{
           builds_duration_analytics: Analytics.build_duration_analytics(project.id, opts),
           builds_p99_durations: Analytics.build_percentile_durations(project.id, 0.99, opts),
           builds_p90_durations: Analytics.build_percentile_durations(project.id, 0.9, opts),
           builds_p50_durations: Analytics.build_percentile_durations(project.id, 0.5, opts)
         }}
      end
    )
    |> assign_async(
      [:total_builds_analytics, :failed_builds_analytics, :build_success_rate_analytics, :analytics_chart_data],
      fn ->
        total_builds_analytics = Analytics.build_analytics(project.id, opts)
        failed_builds_analytics = Analytics.build_analytics(project.id, Keyword.put(opts, :status, "failure"))
        build_success_rate_analytics = Analytics.build_success_rate_analytics(project.id, opts)

        {:ok,
         %{
           total_builds_analytics: total_builds_analytics,
           failed_builds_analytics: failed_builds_analytics,
           build_success_rate_analytics: build_success_rate_analytics,
           analytics_chart_data:
             analytics_chart_data(
               analytics_selected_widget,
               total_builds_analytics,
               failed_builds_analytics,
               build_success_rate_analytics
             )
         }}
      end
    )
  end

  defp analytics_chart_data(
         "total-builds",
         total_builds_analytics,
         _failed_builds_analytics,
         _build_success_rate_analytics
       ) do
    %{
      dates: total_builds_analytics.dates,
      values: total_builds_analytics.values,
      name: dgettext("dashboard_gradle", "Builds"),
      value_formatter: "{value}"
    }
  end

  defp analytics_chart_data(
         "failed-builds",
         _total_builds_analytics,
         failed_builds_analytics,
         _build_success_rate_analytics
       ) do
    %{
      dates: failed_builds_analytics.dates,
      values: failed_builds_analytics.values,
      name: dgettext("dashboard_gradle", "Failed builds"),
      value_formatter: "{value}"
    }
  end

  defp analytics_chart_data(
         _analytics_selected_widget,
         _total_builds_analytics,
         _failed_builds_analytics,
         build_success_rate_analytics
       ) do
    %{
      dates: build_success_rate_analytics.dates,
      values: Enum.map(build_success_rate_analytics.values, &(&1 * 100)),
      name: dgettext("dashboard_gradle", "Build success rate"),
      value_formatter: "{value}%"
    }
  end

  defp environment_label("any"), do: dgettext("dashboard_gradle", "Any")
  defp environment_label("local"), do: dgettext("dashboard_gradle", "Local")
  defp environment_label("ci"), do: dgettext("dashboard_gradle", "CI")

  defp analytics_trend_label("last-24-hours"), do: dgettext("dashboard_gradle", "since yesterday")
  defp analytics_trend_label("last-7-days"), do: dgettext("dashboard_gradle", "since last week")
  defp analytics_trend_label("last-12-months"), do: dgettext("dashboard_gradle", "since last year")
  defp analytics_trend_label("custom"), do: dgettext("dashboard_gradle", "since last period")
  defp analytics_trend_label(_), do: dgettext("dashboard_gradle", "since last month")

  def assign_configuration_insights_options(socket, params) do
    configuration_insights_type = params["configuration-insights-type"] || "gradle-version"

    %{preset: preset, period: period} =
      DatePicker.date_picker_params(params, "configuration-insights")

    socket
    |> assign(:configuration_insights_type, configuration_insights_type)
    |> assign(:configuration_insights_preset, preset)
    |> assign(:configuration_insights_period, period)
  end

  def assign_initial_configuration_insights(%{assigns: %{current_params: current_params}} = socket) do
    assign_configuration_insights(socket, current_params)
  end

  def assign_initial_configuration_insights(socket) do
    socket
  end

  def assign_configuration_insights(socket) do
    assign_configuration_insights(socket, socket.assigns.current_params)
  end

  def assign_configuration_insights(
        %{assigns: %{selected_project: project, configuration_insights_type: configuration_insights_type}} = socket,
        params
      ) do
    %{period: {start_datetime, end_datetime}} = DatePicker.date_picker_params(params, "configuration-insights")

    opts = [start_datetime: start_datetime, end_datetime: end_datetime]

    socket
    |> assign_async(:configuration_insights_analytics, fn ->
      configuration_insights_analytics =
        Analytics.build_duration_analytics_by_category(
          project.id,
          case configuration_insights_type do
            "java-version" -> :java_version
            _ -> :gradle_version
          end,
          opts
        )

      {:ok, %{configuration_insights_analytics: configuration_insights_analytics}}
    end)
    |> push_event("resize", %{})
  end

  def configuration_insights_chart_height(configuration_insights_analytics) do
    Enum.count(configuration_insights_analytics) * 28
  end

  def configuration_insights_label("java-version"), do: dgettext("dashboard_gradle", "Java version")
  def configuration_insights_label(_), do: dgettext("dashboard_gradle", "Gradle version")

  defp assign_recent_builds(%{assigns: %{selected_project: project, selected_account: account}} = socket) do
    {builds, _meta} = Gradle.list_builds(project.id, %{page_size: @recent_builds_page_size})
    builds = Repo.preload(builds, :built_by_account)

    reversed_builds = Enum.reverse(builds)

    recent_builds_chart_data =
      Enum.map(reversed_builds, fn build ->
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

    recent_builds_chart_urls =
      Enum.map(reversed_builds, fn build ->
        ~p"/#{account.name}/#{project.name}/builds/build-runs/#{build.id}"
      end)

    successful_builds_count = Enum.count(builds, &(&1.status == "success"))
    failed_builds_count = Enum.count(builds, &(&1.status == "failure"))

    socket
    |> assign(:builds, builds)
    |> assign(:recent_builds_chart_data, recent_builds_chart_data)
    |> assign(:recent_builds_chart_urls, recent_builds_chart_urls)
    |> assign(:successful_builds_count, successful_builds_count)
    |> assign(:failed_builds_count, failed_builds_count)
  end
end
