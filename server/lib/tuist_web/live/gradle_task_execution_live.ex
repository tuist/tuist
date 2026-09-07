defmodule TuistWeb.GradleTaskExecutionLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Helpers.GradleTask
  import TuistWeb.Runs.RanByBadge

  alias Tuist.Gradle
  alias Tuist.Gradle.ExecutionGraph
  alias Tuist.Repo
  alias Tuist.Utilities.ByteFormatter
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Errors.NotFoundError

  def mount(%{"build_run_id" => build_id, "task_id" => task_id}, _session, socket) do
    project = socket.assigns.selected_project

    with {:ok, task} <- Gradle.get_task(project.id, build_id, task_id),
         {:ok, build} <- Gradle.get_build(build_id),
         true <- build.project_id == project.id do
      {:ok,
       socket
       |> assign(:task, task)
       |> assign(:build, Repo.preload(build, :built_by_account))
       |> assign(:head_title, "#{task.task_path} · Task execution · Tuist")}
    else
      _ -> raise NotFoundError, dgettext("dashboard_gradle", "Task execution not found.")
    end
  end

  defp overview_path(assigns) do
    query =
      URI.encode_query(%{
        root_project_name: assigns.build.root_project_name,
        build_path: assigns.task.build_path,
        task_type: assigns.task.task_type
      })

    "/#{assigns.selected_account.name}/#{assigns.selected_project.name}/builds/tasks/#{URI.encode(assigns.task.task_path, &URI.char_unreserved?/1)}?#{query}"
  end

  defp dependencies_query(task), do: %{tab: "dependencies", node: ExecutionGraph.task_id(task.build_path, task.task_path)}

  defp cacheability(%{cacheability: "disabled"}), do: dgettext("dashboard_gradle", "Not cacheable")
  defp cacheability(%{cacheability: "cacheable"}), do: dgettext("dashboard_gradle", "Cacheable")
  defp cacheability(%{cacheable: true}), do: dgettext("dashboard_gradle", "Cacheable")
  defp cacheability(_), do: dgettext("dashboard_gradle", "Unknown cacheability")

  defp lookup("hit"), do: dgettext("dashboard_gradle", "Hit")
  defp lookup("miss"), do: dgettext("dashboard_gradle", "Miss")
  defp lookup("error"), do: dgettext("dashboard_gradle", "Failed")
  defp lookup("not_requested"), do: dgettext("dashboard_gradle", "Not requested")
  defp lookup(_), do: dgettext("dashboard_gradle", "Unknown")

  defp duration(nil), do: "—"
  defp duration(value), do: DateFormatter.format_duration_from_milliseconds(value)
  defp value(value) when value in [nil, ""], do: "—"
  defp value(value), do: value

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp detail(assigns) do
    ~H"""
    <div data-part="metadata">
      <dt>{@label}</dt>
      <dd>{render_slot(@inner_block)}</dd>
    </div>
    """
  end
end
