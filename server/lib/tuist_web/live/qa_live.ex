defmodule TuistWeb.QALive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.EmptyState

  alias Tuist.QA

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    slug = "#{account.name}/#{project.name}"

    socket =
      socket
      |> assign(:head_title, "#{gettext("Tuist QA")} · #{slug} · Tuist")
      |> assign(:qa_runs, [])
      |> load_qa_runs()

    {:ok, socket}
  end

  defp load_qa_runs(socket) do
    project = socket.assigns.selected_project
    qa_runs = QA.qa_runs_for_project(project)

    assign(socket, :qa_runs, qa_runs)
  end

  defp map_status_to_badge_color("failed"), do: "destructive"
  defp map_status_to_badge_color("completed"), do: "success"
  defp map_status_to_badge_color("running"), do: "focus"
  defp map_status_to_badge_color("pending"), do: "warning"
  defp map_status_to_badge_color(_), do: "secondary"

  defp format_datetime(datetime) when is_struct(datetime, DateTime) do
    Timex.from_now(datetime)
  end

  defp format_datetime(_), do: "Unknown"

  def empty_state_light_background(assigns) do
    ~H"""
    <svg
      width="358"
      height="253"
      viewBox="0 0 358 253"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <g opacity="0.4">
        <path
          d="M71.5 126.5C71.5 161.294 99.2061 189 134 189C168.794 189 196.5 161.294 196.5 126.5C196.5 91.7061 168.794 64 134 64C99.2061 64 71.5 91.7061 71.5 126.5Z"
          stroke="#E5E5E5"
        />
      </g>
    </svg>
    """
  end

  def empty_state_dark_background(assigns) do
    ~H"""
    <svg
      width="358"
      height="253"
      viewBox="0 0 358 253"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <g opacity="0.4">
        <path
          d="M71.5 126.5C71.5 161.294 99.2061 189 134 189C168.794 189 196.5 161.294 196.5 126.5C196.5 91.7061 168.794 64 134 64C99.2061 64 71.5 91.7061 71.5 126.5Z"
          stroke="#404040"
        />
      </g>
    </svg>
    """
  end
end