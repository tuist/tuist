defmodule TuistWeb.BuildsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Runs.RanByBadge

  alias Tuist.Runs
  alias Tuist.Runs.Analytics
  alias TuistWeb.Utilities.Query

  def mount(params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    socket =
      socket
      |> assign(
        :head_title,
        "#{gettext("Builds")} · #{account.name}/#{project.name} · Tuist"
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
              "analytics-build-category"
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
    analytics_date_range = params["analytics-date-range"] || "last-30-days"
    analytics_build_scheme = params["analytics-build-scheme"] || "any"
    analytics_build_category = params["analytics-build-category"] || "any"

    start_date = start_date(analytics_date_range)

    opts = [
      project_id: project.id,
      start_date: start_date
    ]

    opts =
      opts
      |> opts_with_analytics_build_scheme(analytics_build_scheme)
      |> opts_with_analytics_build_category(analytics_build_category)

    opts =
      case analytics_environment do
        "ci" -> Keyword.put(opts, :is_ci, true)
        "local" -> Keyword.put(opts, :is_ci, false)
        _ -> opts
      end

    analytics_tasks = [
      Task.async(fn -> Analytics.builds_duration_analytics(project.id, opts) end),
      Task.async(fn -> Analytics.builds_percentile_durations(project.id, 0.99, opts) end),
      Task.async(fn -> Analytics.builds_percentile_durations(project.id, 0.9, opts) end),
      Task.async(fn -> Analytics.builds_percentile_durations(project.id, 0.5, opts) end),
      Task.async(fn -> Analytics.builds_analytics(project.id, opts) end),
      Task.async(fn ->
        Analytics.builds_analytics(project.id, Keyword.put(opts, :status, :failure))
      end),
      Task.async(fn -> Analytics.builds_success_rate_analytics(project.id, opts) end)
    ]

    [
      builds_duration_analytics,
      builds_p99_durations,
      builds_p90_durations,
      builds_p50_durations,
      total_builds_analytics,
      failed_builds_analytics,
      build_success_rate_analytics
    ] = Task.await_many(analytics_tasks, 10_000)

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
      trend_label(analytics_date_range)
    )
    |> assign(:analytics_environment, analytics_environment)
    |> assign(:analytics_date_range, analytics_date_range)
    |> assign(:analytics_build_scheme, analytics_build_scheme)
    |> assign(:analytics_build_category, analytics_build_category)
    |> assign(:build_schemes, Tuist.Runs.project_build_schemes(project))
  end

  defp opts_with_analytics_build_scheme(opts, analytics_build_scheme) do
    case analytics_build_scheme do
      "any" -> opts
      scheme -> Keyword.put(opts, :scheme, scheme)
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

    configuration_insights_date_range =
      params["configuration-insights-date-range"] || "last-30-days"

    socket =
      socket
      |> assign(:configuration_insights_type, configuration_insights_type)
      |> assign(:configuration_insights_date_range, configuration_insights_date_range)

    configuration_insights_analytics =
      Analytics.builds_duration_analytics_grouped_by_category(
        project.id,
        case configuration_insights_type do
          "macos-version" -> :macos_version
          "device" -> :model_identifier
          _ -> :xcode_version
        end,
        start_date: start_date(configuration_insights_date_range)
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

    socket
    |> assign(:recent_builds, recent_builds)
    |> assign(:recent_builds_chart_data, recent_builds_chart_data)
    |> assign(:successful_builds_count, Enum.count(recent_builds, &(&1.status == :success)))
    |> assign(:failed_builds_count, Enum.count(recent_builds, &(&1.status == :failure)))
  end

  defp start_date("last-12-months"), do: Date.add(DateTime.utc_now(), -365)
  defp start_date("last-30-days"), do: Date.add(DateTime.utc_now(), -30)
  defp start_date("last-7-days"), do: Date.add(DateTime.utc_now(), -7)

  defp trend_label("last-7-days"), do: gettext("since last week")
  defp trend_label("last-12-months"), do: gettext("since last year")
  defp trend_label(_), do: gettext("since last month")

  defp environment_label("any"), do: gettext("Any")
  defp environment_label("local"), do: gettext("Local")
  defp environment_label("ci"), do: gettext("CI")

  defp configuration_insights_label("xcode-version"), do: gettext("Xcode version")
  defp configuration_insights_label("macos-version"), do: gettext("macOS version")
  defp configuration_insights_label("device"), do: gettext("Device")

  defp build_scheme_label("any"), do: gettext("Any")
  defp build_scheme_label(scheme), do: scheme

  defp type_labels(type, configuration_insights_analytics) do
    labels = Enum.map(configuration_insights_analytics, & &1.category)

    labels =
      case type do
        "device" -> Enum.map(labels, &(Tuist.Apple.devices()[&1] || gettext("Unknown")))
        _ -> labels
      end

    labels
  end
end
