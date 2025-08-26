defmodule TuistWeb.QARunDetailLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.QA

  def mount(%{"qa_run_id" => qa_run_id}, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    case QA.qa_run(qa_run_id) do
      {:ok, qa_run} ->
        if qa_run.app_build.preview.project.id == project.id do
          slug = "#{account.name}/#{project.name}"

          socket =
            socket
            |> assign(:head_title, "#{gettext("QA Run")} · #{slug} · Tuist")
            |> assign(:qa_run, qa_run)

          {:ok, socket}
        else
          raise TuistWeb.Errors.NotFoundError, gettext("QA run not found")
        end

      {:error, _} ->
        raise TuistWeb.Errors.NotFoundError, gettext("QA run not found")
    end
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
end