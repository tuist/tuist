defmodule TuistWeb.OverviewLive do
  use TuistWeb, :live_view
  use TuistWeb.Noora
  alias Tuist.Runs.Analytics
  alias Tuist.Projects

  def mount(_params, _session, %{assigns: %{selected_project: project}} = socket) do
    {:ok,
     socket
     |> assign(
       :head_title,
       "#{gettext("Overview")} · #{Projects.get_project_slug_from_id(project.id)} · Tuist"
     )
     |> assign(
       :binary_cache_hit_rate_analytics,
       Analytics.cache_hit_rate_analytics(project_id: project.id)
     )
     |> assign(
       :selective_testing_analytics,
       Analytics.selective_testing_analytics(project_id: project.id)
     )
     |> assign(
       :build_analytics,
       Analytics.builds_duration_analytics(project.id)
     )
     |> assign(
       :test_analytics,
       Analytics.runs_duration_analytics("test", project_id: project.id)
     )}
  end
end
