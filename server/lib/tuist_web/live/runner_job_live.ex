defmodule TuistWeb.RunnerJobLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Authorization
  alias Tuist.Runners.Jobs
  alias Tuist.Utilities.DateFormatter

  @impl true
  def mount(
        %{"workflow_job_id" => workflow_job_id_param},
        _session,
        %{assigns: %{selected_account: selected_account, current_user: current_user}} = socket
      ) do
    if Authorization.authorize(:projects_read, current_user, selected_account) != :ok do
      raise TuistWeb.Errors.NotFoundError,
            dgettext("dashboard_runners", "The page you are looking for doesn't exist or has been moved.")
    end

    workflow_job_id = parse_workflow_job_id(workflow_job_id_param)

    case Jobs.get_for_account(selected_account.id, workflow_job_id) do
      {:ok, job} ->
        head_title =
          "#{job_title(job)} · #{dgettext("dashboard_runners", "Jobs")} · #{selected_account.name} · Tuist"

        {:ok,
         socket
         |> assign(:head_title, head_title)
         |> assign(:job, job)}

      {:error, :not_found} ->
        raise TuistWeb.Errors.NotFoundError,
              dgettext("dashboard_runners", "The job you are looking for doesn't exist or has been moved.")
    end
  end

  defp parse_workflow_job_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} ->
        id

      _ ->
        raise TuistWeb.Errors.NotFoundError,
              dgettext("dashboard_runners", "The job you are looking for doesn't exist or has been moved.")
    end
  end

  defp job_title(%{workflow_name: workflow, job_name: job}) when workflow != "" and job != "",
    do: "#{workflow} › #{job}"

  defp job_title(%{job_name: job}) when job != "", do: job
  defp job_title(%{workflow_job_id: id}), do: "Job ##{id}"

  def header_title(job), do: job_title(job)

  def status_badge_props("queued"), do: %{label: dgettext("dashboard_runners", "Queued"), status: "warning"}
  def status_badge_props("claimed"), do: %{label: dgettext("dashboard_runners", "Claimed"), status: "in_progress"}
  def status_badge_props("running"), do: %{label: dgettext("dashboard_runners", "Running"), status: "in_progress"}
  def status_badge_props("completed"), do: %{label: dgettext("dashboard_runners", "Completed"), status: "success"}
  def status_badge_props(_), do: %{label: dgettext("dashboard_runners", "Unknown"), status: "warning"}

  def conclusion_badge_props("success"), do: %{label: dgettext("dashboard_runners", "Success"), status: "success"}
  def conclusion_badge_props("failure"), do: %{label: dgettext("dashboard_runners", "Failure"), status: "error"}
  def conclusion_badge_props("cancelled"), do: %{label: dgettext("dashboard_runners", "Cancelled"), status: "warning"}
  def conclusion_badge_props("skipped"), do: %{label: dgettext("dashboard_runners", "Skipped"), status: "warning"}

  def conclusion_badge_props(other) when is_binary(other) and other != "",
    do: %{label: String.capitalize(other), status: "warning"}

  def conclusion_badge_props(_), do: nil

  def queued_duration_ms(%{enqueued_at: enqueued, claimed_at: claimed}) do
    cond do
      epoch?(enqueued) -> 0
      epoch?(claimed) -> ms_since(enqueued)
      true -> DateTime.diff(claimed, enqueued, :millisecond)
    end
  end

  def claim_duration_ms(%{claimed_at: claimed, started_at: started}) do
    cond do
      epoch?(claimed) -> 0
      epoch?(started) -> ms_since(claimed)
      true -> DateTime.diff(started, claimed, :millisecond)
    end
  end

  def run_duration_ms(%{started_at: started, completed_at: completed}) do
    cond do
      epoch?(started) -> 0
      epoch?(completed) -> ms_since(started)
      true -> DateTime.diff(completed, started, :millisecond)
    end
  end

  def total_duration_ms(%{enqueued_at: enqueued, completed_at: completed}) do
    cond do
      epoch?(enqueued) -> 0
      epoch?(completed) -> ms_since(enqueued)
      true -> DateTime.diff(completed, enqueued, :millisecond)
    end
  end

  defp ms_since(nil), do: 0

  defp ms_since(%DateTime{} = ts) do
    if epoch?(ts), do: 0, else: DateTime.diff(DateTime.utc_now(), ts, :millisecond)
  end

  defp epoch?(%DateTime{year: 1970, month: 1, day: 1}), do: true
  defp epoch?(nil), do: true
  defp epoch?(_), do: false

  def format_duration(ms) when is_integer(ms) and ms > 0, do: DateFormatter.format_duration_from_milliseconds(ms)
  def format_duration(_), do: "–"

  def format_timestamp(%DateTime{} = ts) do
    if epoch?(ts), do: "–", else: DateFormatter.from_now(ts)
  end

  def format_timestamp(_), do: "–"

  def format_absolute(%DateTime{} = ts) do
    if epoch?(ts), do: "–", else: Calendar.strftime(ts, "%Y-%m-%d %H:%M:%S UTC")
  end

  def format_absolute(_), do: "–"

  def display(""), do: "–"
  def display(nil), do: "–"
  def display(value) when is_binary(value), do: value
  def display(value), do: to_string(value)
end
