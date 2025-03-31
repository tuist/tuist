defmodule TuistWeb.OverviewLive do
  use TuistWeb, :live_view
  use TuistWeb.Noora
  alias Tuist.Runs.Analytics
  alias Tuist.Projects

  def mount(params, _session, %{assigns: %{selected_project: project}} = socket) do
    {:ok,
     socket
     |> assign(
       :head_title,
       "#{gettext("Overview")} · #{Projects.get_project_slug_from_id(project.id)} · Tuist"
     )}
  end

  def handle_params(params, _uri, %{assigns: %{selected_project: project}} = socket) do
    {
      :noreply,
      socket
      |> assign_analytics(params)
    }
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
      analytics_environment_label(analytics_environment)
    )
    |> assign(
      :binary_cache_hit_rate_analytics,
      Analytics.cache_hit_rate_analytics(opts)
    )
    |> assign(
      :selective_testing_analytics,
      Analytics.selective_testing_analytics(opts)
    )
    |> assign(
      :build_analytics,
      Analytics.builds_duration_analytics(project.id, opts)
    )
    |> assign(
      :test_analytics,
      Analytics.runs_duration_analytics("test", project_id: project.id)
    )
  end

  defp analytics_trend_label("last_7_days"), do: gettext("since last week")
  defp analytics_trend_label("last_12_months"), do: gettext("since last year")
  defp analytics_trend_label(_), do: gettext("since last month")

  defp analytics_environment_label("any") do
    gettext("Any")
  end

  defp analytics_environment_label("local") do
    gettext("Local")
  end

  defp analytics_environment_label("ci") do
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
end
