defmodule TuistWeb.GradleBuildLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Runs.RanByBadge

  alias Tuist.Gradle
  alias Tuist.Repo
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Errors.NotFoundError

  def mount(
        %{"gradle_build_id" => build_id},
        _session,
        %{assigns: %{selected_project: project, selected_account: account}} = socket
      ) do
    build = Gradle.get_build(build_id)

    if is_nil(build) or build.project_id != project.id do
      raise NotFoundError, dgettext("dashboard_gradle", "Build not found.")
    end

    build = Repo.preload(build, :built_by_account)

    tasks = Gradle.list_tasks(build_id)
    slug = "#{account.name}/#{project.name}"

    title = build.root_project_name || dgettext("dashboard_gradle", "Gradle Build")

    socket =
      socket
      |> assign(:build, build)
      |> assign(:tasks, tasks)
      |> assign(:title, title)
      |> assign(:head_title, "#{title} · #{slug} · Tuist")

    {:ok, socket}
  end

  defp cache_hit_rate(build) do
    from_cache = (build.tasks_local_hit_count || 0) + (build.tasks_remote_hit_count || 0)
    executed = build.tasks_executed_count || 0
    total = from_cache + executed

    if total == 0 do
      0.0
    else
      Float.round(from_cache / total * 100.0, 1)
    end
  end

  defp avoidance_rate(build) do
    from_cache = (build.tasks_local_hit_count || 0) + (build.tasks_remote_hit_count || 0)
    up_to_date = build.tasks_up_to_date_count || 0
    executed = build.tasks_executed_count || 0
    failed = build.tasks_failed_count || 0
    skipped = build.tasks_skipped_count || 0
    no_source = build.tasks_no_source_count || 0
    total = from_cache + up_to_date + executed + failed + skipped + no_source

    if total == 0 do
      0.0
    else
      Float.round((from_cache + up_to_date) / total * 100.0, 1)
    end
  end

  defp outcome_color("local_hit"), do: "success"
  defp outcome_color("remote_hit"), do: "information"
  defp outcome_color("up_to_date"), do: "information"
  defp outcome_color("executed"), do: "secondary"
  defp outcome_color("failed"), do: "destructive"
  defp outcome_color(_), do: "secondary"

  defp outcome_label("local_hit"), do: dgettext("dashboard_gradle", "Local hit")
  defp outcome_label("remote_hit"), do: dgettext("dashboard_gradle", "Remote hit")
  defp outcome_label("up_to_date"), do: dgettext("dashboard_gradle", "Up-to-date")
  defp outcome_label("executed"), do: dgettext("dashboard_gradle", "Executed")
  defp outcome_label("failed"), do: dgettext("dashboard_gradle", "Failed")
  defp outcome_label("skipped"), do: dgettext("dashboard_gradle", "Skipped")
  defp outcome_label("no_source"), do: dgettext("dashboard_gradle", "No source")
  defp outcome_label(other), do: other

  defp format_duration(duration_ms) do
    DateFormatter.format_duration_from_milliseconds(duration_ms)
  end
end
