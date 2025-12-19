defmodule TuistWeb.OpsQALogsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.QA
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Errors.NotFoundError

  @impl true
  def mount(%{"qa_run_id" => qa_run_id}, _session, socket) do
    case QA.qa_run_for_ops(qa_run_id) do
      nil ->
        raise NotFoundError, dgettext("dashboard_qa", "QA run not found")

      qa_run ->
        logs = QA.logs_for_run(qa_run_id)
        formatted_logs = QA.prepare_and_format_logs(logs)

        if connected?(socket) do
          Tuist.PubSub.subscribe("qa_logs:#{qa_run_id}")
        end

        {:ok,
         socket
         |> assign(:qa_run, qa_run)
         |> assign(:logs, logs)
         |> assign(:formatted_logs, formatted_logs)
         |> assign(:head_title, "#{dgettext("dashboard_qa", "QA Logs")} · #{qa_run.project_name} · Tuist")}
    end
  end

  @impl true
  def handle_info({:qa_log_created, log}, socket) do
    current_logs = socket.assigns.logs
    log = %{log | inserted_at: NaiveDateTime.utc_now()}
    updated_logs = current_logs ++ [log]
    updated_formatted_logs = QA.prepare_and_format_logs(updated_logs)

    {:noreply,
     socket
     |> assign(:logs, updated_logs)
     |> assign(:formatted_logs, updated_formatted_logs)}
  end

  def handle_info(_event, socket) do
    {:noreply, socket}
  end

  defp map_qa_status_to_badge_status("failed"), do: "error"
  defp map_qa_status_to_badge_status("completed"), do: "success"
  defp map_qa_status_to_badge_status("running"), do: "attention"
  defp map_qa_status_to_badge_status("pending"), do: "warning"
  defp map_qa_status_to_badge_status(_), do: "disabled"
end
