defmodule TuistWeb.BuildsLive do
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

  def mount(params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    socket =
      socket
      |> assign(
        :head_title,
        "#{dgettext("dashboard_builds", "Builds")} · #{account.name}/#{project.name} · Tuist"
      )
      |> assign_configuration_insights_options(params)
      |> assign_initial_configuration_insights()
      |> assign_recent_builds()

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
              "analytics-selected-widget",
              "analytics-environment",
              "analytics-date-range",
              "analytics-build-scheme",
              "analytics-build-configuration",
              "analytics-build-category",
              "build-duration-type"
            ])
          )
      )

    {
      :noreply,
      socket
      |> assign(
        :uri,
        uri
      )
      |> assign(:current_params, params)
      |> assign_analytics(params)
      |> assign_configuration_insights_options(params)
      |> assign_configuration_insights()
    }
  end

  defp assign_analytics(%{assigns: %{selected_project: project}} = socket, params) do
    analytics_environment = params["analytics-environment"] || "any"
    analytics_build_scheme = params["analytics-build-scheme"] || "any"
    analytics_build_configuration = params["analytics-build-configuration"] || "any"
    analytics_build_category = params["analytics-build-category"] || "any"

    %{preset: preset, period: {start_datetime, end_datetime} = period} =
      DatePicker.date_picker_params(params, "analytics")

    opts = [project_id: project.id, start_datetime: start_datetime, end_datetime: end_datetime]

    opts =
      opts
      |> opts_with_analytics_build_scheme(analytics_build_scheme)
      |> opts_with_analytics_build_configuration(analytics_build_configuration)
      |> opts_with_analytics_build_category(analytics_build_category)

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
    |> assign(:build_schemes, Runs.project_build_schemes(project))
    |> assign(:build_configurations, Runs.project_build_configurations(project))
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
    # We update the actual analytics after 50 milliseconds to preserve the chart animation
    Process.send_after(self(), :update_configuration_insights, 0)

    push_event(socket, "resize", %{})
  end

  def handle_info(:update_configuration_insights, socket) do
    {:noreply,
     assign(
       socket,
       :configuration_insights_analytics,
       socket.assigns.next_configuration_insights_analytics
     )}
  end

  def handle_info({:build_created, _build}, socket) do
    # Only update when pagination is inactive
    if Query.has_pagination_params?(socket.assigns.uri.query) do
      {:noreply, socket}
    else
      {:noreply, socket |> assign_analytics(socket.assigns.current_params) |> assign_recent_builds()}
    end
  end

  def handle_info(_event, socket) do
    {:noreply, socket}
  end

  def handle_event(
        "select_build_duration_type",
        %{"type" => type},
        %{assigns: %{selected_account: selected_account, selected_project: selected_project, uri: uri}} = socket
      ) do
    socket =
      push_patch(
        socket,
        to:
          "/#{selected_account.name}/#{selected_project.name}/builds?#{Query.put(uri.query, "build-duration-type", type)}",
        replace: true
      )

    {:noreply, socket}
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
          "/#{selected_account.name}/#{selected_project.name}/builds?#{Query.put(uri.query, "analytics-selected-widget", widget)}",
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

    {:noreply, push_patch(socket, to: "/#{selected_account.name}/#{selected_project.name}/builds?#{query_params}")}
  end

  def handle_event(
        "configuration_insights_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        %{assigns: %{selected_account: selected_account, selected_project: selected_project}} = socket
      ) do
    query_params =
      if preset == "custom" do
        socket.assigns.uri.query
        |> Query.put("configuration-insights-date-range", "custom")
        |> Query.put("configuration-insights-start-date", start_date)
        |> Query.put("configuration-insights-end-date", end_date)
      else
        Query.put(socket.assigns.uri.query, "configuration-insights-date-range", preset)
      end

    {:noreply, push_patch(socket, to: "/#{selected_account.name}/#{selected_project.name}/builds?#{query_params}")}
  end

  defp assign_recent_builds(%{assigns: %{selected_project: project}} = socket) do
    {recent_builds, _meta} =
      Runs.list_build_runs(
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
            :success -> "var:noora-chart-primary"
            :failure -> "var:noora-chart-destructive"
          end

        value = run.duration

        %{value: value, itemStyle: %{color: color}, date: run.inserted_at}
      end)

    %{successful_count: successful_builds_count, failed_count: failed_builds_count} =
      Runs.recent_build_status_counts(project.id, limit: 40)

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

  defp environment_label("any"), do: dgettext("dashboard_builds", "Any")
  defp environment_label("local"), do: dgettext("dashboard_builds", "Local")
  defp environment_label("ci"), do: dgettext("dashboard_builds", "CI")

  defp configuration_insights_label("xcode-version"), do: dgettext("dashboard_builds", "Xcode version")
  defp configuration_insights_label("macos-version"), do: dgettext("dashboard_builds", "macOS version")
  defp configuration_insights_label("device"), do: dgettext("dashboard_builds", "Device")

  defp build_scheme_label("any"), do: dgettext("dashboard_builds", "Any")
  defp build_scheme_label(scheme), do: scheme

  defp build_configuration_label("any"), do: dgettext("dashboard_builds", "Any")
  defp build_configuration_label(configuration), do: configuration

  defp type_labels(type, configuration_insights_analytics) do
    labels = Enum.map(configuration_insights_analytics, & &1.category)

    labels =
      case type do
        "device" -> Enum.map(labels, &(Tuist.Apple.devices()[&1] || dgettext("dashboard_builds", "Unknown")))
        _ -> labels
      end

    labels
  end
end
