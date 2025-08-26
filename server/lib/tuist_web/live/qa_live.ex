defmodule TuistWeb.QALive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Previews.PlatformIcon

  alias Tuist.AppBuilds.Preview
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
    qa_runs = QA.qa_runs_for_project(project, preload: [
      app_build: [
        preview: []
      ],
      run_steps: []
    ])

    assign(socket, :qa_runs, qa_runs)
  end



  defp format_datetime(datetime) when is_struct(datetime, DateTime) do
    Timex.from_now(datetime)
  end

  defp format_datetime(_), do: "Unknown"
end
