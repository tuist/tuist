defmodule TuistWeb.XcodeBuildsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.PercentileDropdownWidget
  import TuistWeb.Runs.RanByBadge

  alias Tuist.Builds
  alias Tuist.Builds.Analytics
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Utilities.Query

  def assign_mount(socket, params) do
    socket
    |> assign_configuration_insights_options(params)
    |> assign_initial_configuration_insights()
    |> assign_recent_builds()
  end

  def assign_handle_params(socket, params) do
    uri =
      URI.new!(
        "?" <>
          URI.encode_query(
            Map.take(params, [
              "analytics-selected-widget",
              "analytics-environment",
              "analytics-date-range",
              "analytics-build-scheme",
              "analytics-build-configuration",
              "analytics-build-category",
              "analytics-build-tag",
              "build-duration-type"
            ])
          )
      )

    socket
    |> assign(:uri, uri)
    |> assign(:current_params, params)
    |> assign_analytics(params)
    |> assign_configuration_insights_options(params)
    |> assign_configuration_insights()
  end

  def handle_info_build_created(socket) do
    if Query.has_pagination_params?(socket.assigns.uri.query) do
      socket
    else
      socket |> assign_analytics(socket.assigns.current_params) |> assign_recent_builds()
    end
  end

  def handle_info_update_configuration_insights(socket) do
    assign(
      socket,
      :configuration_insights_analytics,
      socket.assigns.next_configuration_insights_analytics
    )
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp assign_analytics(%{assigns: %{selected_project: project}} = socket, params) do
    analytics_environment = params["analytics-environment"] || "any"
    analytics_build_scheme = params["analytics-build-scheme"] || "any"
    analytics_build_configuration = params["analytics-build-configuration"] || "any"
    analytics_build_category = params["analytics-build-category"] || "any"
    analytics_build_tag = params["analytics-build-tag"] || "all"

    %{preset: preset, period: {start_datetime, end_datetime} = period} =
      DatePicker.date_picker_params(params, "analytics")

    opts = [project_id: project.id, start_datetime: start_datetime, end_datetime: end_datetime]

    opts =
      opts
      |> opts_with_analytics_build_scheme(analytics_build_scheme)
      |> opts_with_analytics_build_configuration(analytics_build_configuration)
      |> opts_with_analytics_build_category(analytics_build_category)
      |> opts_with_analytics_build_tag(analytics_build_tag)

    opts =
      case analytics_environment do
        "ci" -> Keyword.put(opts, :is_ci, true)
        "local" -> Keyword.put(opts, :is_ci, false)
        _ -> opts
      end

    [
      builds_duration_analytics,
      builds_p99_durations,
      builds_p90_durations,
      builds_p50_durations,
      total_builds_analytics,
      failed_builds_analytics,
      build_success_rate_analytics
    ] = Analytics.combined_builds_analytics(project.id, opts)

    socket
    |> assign(:builds_duration_analytics, builds_duration_analytics)
    |> assign(:builds_p99_durations, builds_p99_durations)
    |> assign(:builds_p90_durations, builds_p90_durations)
    |> assign(:builds_p50_durations, builds_p50_durations)
    |> assign(:total_builds_analytics, total_builds_analytics)
    |> assign(:failed_builds_analytics, failed_builds_analytics)
    |> assign(:build_success_rate_analytics, build_success_rate_analytics)
    |> assign(
      :analytics_selected_widget,
      params["analytics-selected-widget"] || "build-duration"
    )
    |> assign(
      :analytics_trend_label,
      trend_label(preset)
    )
    |> assign(:analytics_environment, analytics_environment)
    |> assign(:analytics_preset, preset)
    |> assign(:analytics_period, period)
    |> assign(:analytics_build_scheme, analytics_build_scheme)
    |> assign(:analytics_build_configuration, analytics_build_configuration)
    |> assign(:analytics_build_category, analytics_build_category)
    |> assign(:analytics_build_tag, analytics_build_tag)
    |> assign(:build_schemes, Builds.project_build_schemes(project))
    |> assign(:build_configurations, Builds.project_build_configurations(project))
    |> assign(:build_tags, Builds.project_build_tags(project))
    |> assign(:selected_build_duration_type, params["build-duration-type"] || "avg")
  end

  defp opts_with_analytics_build_scheme(opts, analytics_build_scheme) do
    case analytics_build_scheme do
      "any" -> opts
      scheme -> Keyword.put(opts, :scheme, scheme)
    end
  end

  defp opts_with_analytics_build_configuration(opts, analytics_build_configuration) do
    case analytics_build_configuration do
      "any" -> opts
      configuration -> Keyword.put(opts, :configuration, configuration)
    end
  end

  defp opts_with_analytics_build_category(opts, analytics_build_category) do
    case analytics_build_category do
      "any" -> opts
      category -> Keyword.put(opts, :category, category)
    end
  end

  defp opts_with_analytics_build_tag(opts, analytics_build_tag) do
    case analytics_build_tag do
      "all" -> opts
      tag -> Keyword.put(opts, :tag, tag)
    end
  end

  defp assign_initial_configuration_insights(
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

  defp assign_configuration_insights_options(%{assigns: %{selected_project: project}} = socket, params) do
    configuration_insights_type = params["configuration-insights-type"] || "xcode-version"

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
          "macos-version" -> :macos_version
          "device" -> :model_identifier
          _ -> :xcode_version
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

  defp assign_configuration_insights(socket) do
    Process.send_after(self(), :update_configuration_insights, 0)

    push_event(socket, "resize", %{})
  end

  defp assign_recent_builds(%{assigns: %{selected_project: project}} = socket) do
    {recent_builds, _meta} =
      Builds.list_build_runs(
        %{
          first: 40,
          filters: [
            %{field: :project_id, op: :==, value: project.id}
          ],
          order_by: [:inserted_at],
          order_directions: [:desc]
        },
        preload: [:ran_by_account]
      )

    recent_builds_chart_data =
      Enum.map(recent_builds, fn run ->
        color =
          case run.status do
            "success" -> "var:noora-chart-primary"
            "failure" -> "var:noora-chart-destructive"
          end

        value = run.duration

        %{value: value, itemStyle: %{color: color}, date: run.inserted_at}
      end)

    %{successful_count: successful_builds_count, failed_count: failed_builds_count} =
      Builds.recent_build_status_counts(project.id, limit: 40)

    socket
    |> assign(:recent_builds, recent_builds)
    |> assign(:recent_builds_chart_data, recent_builds_chart_data)
    |> assign(:successful_builds_count, successful_builds_count)
    |> assign(:failed_builds_count, failed_builds_count)
  end

  defp trend_label("last-24-hours"), do: dgettext("dashboard_builds", "since yesterday")
  defp trend_label("last-7-days"), do: dgettext("dashboard_builds", "since last week")
  defp trend_label("last-12-months"), do: dgettext("dashboard_builds", "since last year")
  defp trend_label("custom"), do: dgettext("dashboard_builds", "since last period")
  defp trend_label(_), do: dgettext("dashboard_builds", "since last month")

  def environment_label("any"), do: dgettext("dashboard_builds", "Any")
  def environment_label("local"), do: dgettext("dashboard_builds", "Local")
  def environment_label("ci"), do: dgettext("dashboard_builds", "CI")

  def configuration_insights_label("xcode-version"), do: dgettext("dashboard_builds", "Xcode version")
  def configuration_insights_label("macos-version"), do: dgettext("dashboard_builds", "macOS version")
  def configuration_insights_label("device"), do: dgettext("dashboard_builds", "Device")

  def build_scheme_label("any"), do: dgettext("dashboard_builds", "Any")
  def build_scheme_label(scheme), do: scheme

  def build_configuration_label("any"), do: dgettext("dashboard_builds", "Any")
  def build_configuration_label(configuration), do: configuration

  def build_tag_label("all"), do: dgettext("dashboard_builds", "All")
  def build_tag_label(tag), do: tag

  def type_labels(type, configuration_insights_analytics) do
    labels = Enum.map(configuration_insights_analytics, & &1.category)

    case type do
      "device" -> Enum.map(labels, &(Tuist.Apple.devices()[&1] || dgettext("dashboard_builds", "Unknown")))
      _ -> labels
    end
  end
end
