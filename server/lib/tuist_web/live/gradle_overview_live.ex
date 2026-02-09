defmodule TuistWeb.GradleOverviewLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection

  alias Tuist.Gradle.Analytics, as: GradleAnalytics
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

    [cache_hit_rate_analytics, build_duration_analytics] =
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
  end

  defp analytics_trend_label("last-24-hours"), do: dgettext("dashboard_gradle", "since yesterday")
  defp analytics_trend_label("last-7-days"), do: dgettext("dashboard_gradle", "since last week")
  defp analytics_trend_label("last-12-months"), do: dgettext("dashboard_gradle", "since last year")
  defp analytics_trend_label("custom"), do: dgettext("dashboard_gradle", "since last period")
  defp analytics_trend_label(_), do: dgettext("dashboard_gradle", "since last month")

  defp environment_label("any"), do: dgettext("dashboard_gradle", "Any")
  defp environment_label("local"), do: dgettext("dashboard_gradle", "Local")
  defp environment_label("ci"), do: dgettext("dashboard_gradle", "CI")

  defp combined_overview_analytics(project_id, opts) do
    queries = [
      fn -> GradleAnalytics.cache_hit_rate_analytics(project_id, opts) end,
      fn -> GradleAnalytics.build_duration_analytics(project_id, opts) end
    ]

    Tuist.Tasks.parallel_tasks(queries)
  end
end
