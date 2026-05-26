defmodule TuistWeb.RunnerJobLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.Runners.Jobs
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Errors.NotFoundError

  @impl true
  def mount(
        %{"workflow_job_id" => workflow_job_id_param},
        _session,
        %{assigns: %{selected_account: selected_account, current_user: current_user}} = socket
      ) do
    if Authorization.authorize(:projects_read, current_user, selected_account) != :ok or
         not FeatureFlags.runners_enabled?(selected_account) do
      raise NotFoundError,
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
        raise NotFoundError,
              dgettext("dashboard_runners", "The job you are looking for doesn't exist or has been moved.")
    end
  end

  defp parse_workflow_job_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} ->
        id

      _ ->
        raise NotFoundError,
              dgettext("dashboard_runners", "The job you are looking for doesn't exist or has been moved.")
    end
  end

  defp job_title(%{workflow_name: workflow, job_name: job}) when workflow != "" and job != "", do: "#{workflow} · #{job}"

  defp job_title(%{job_name: job}) when job != "", do: job
  defp job_title(%{workflow_job_id: id}), do: "Job ##{id}"

  def header_title(job), do: job_title(job)

  def header_status(%{status: "completed", conclusion: conclusion}) do
    case conclusion do
      "success" -> :success
      "failure" -> :failure
      "cancelled" -> :warning
      "skipped" -> :warning
      _ -> :warning
    end
  end

  def header_status(%{status: "queued"}), do: :processing
  def header_status(%{status: "claimed"}), do: :processing
  def header_status(%{status: "running"}), do: :processing
  def header_status(_), do: :processing

  def status_badge_props(%{status: "completed", conclusion: "success"}),
    do: %{label: dgettext("dashboard_runners", "Passed"), color: "success"}

  def status_badge_props(%{status: "completed", conclusion: "failure"}),
    do: %{label: dgettext("dashboard_runners", "Failed"), color: "destructive"}

  def status_badge_props(%{status: "completed", conclusion: "cancelled"}),
    do: %{label: dgettext("dashboard_runners", "Cancelled"), color: "warning"}

  def status_badge_props(%{status: "completed", conclusion: "skipped"}),
    do: %{label: dgettext("dashboard_runners", "Skipped"), color: "warning"}

  def status_badge_props(%{status: "queued"}), do: %{label: dgettext("dashboard_runners", "Queued"), color: "warning"}

  def status_badge_props(%{status: "claimed"}),
    do: %{label: dgettext("dashboard_runners", "Claimed"), color: "information"}

  def status_badge_props(%{status: "running"}),
    do: %{label: dgettext("dashboard_runners", "Running"), color: "information"}

  def status_badge_props(_), do: %{label: dgettext("dashboard_runners", "Unknown"), color: "neutral"}

  def platform_label(fleet_name) when is_binary(fleet_name) do
    cond do
      String.starts_with?(fleet_name, "macos-") -> dgettext("dashboard_runners", "macOS")
      String.starts_with?(fleet_name, "linux-") -> dgettext("dashboard_runners", "Linux")
      true -> dgettext("dashboard_runners", "Unknown")
    end
  end

  def platform_label(_), do: dgettext("dashboard_runners", "Unknown")

  @doc """
  Noora badge color paired with `platform_label/1` so the Platform
  field in the CI Details card reads the same as the Platform column
  on the Jobs table — `information` (cool blue) for macOS,
  `attention` (warm yellow) for Linux.
  """
  def platform_badge_color(fleet_name) when is_binary(fleet_name) do
    cond do
      String.starts_with?(fleet_name, "macos-") -> "information"
      String.starts_with?(fleet_name, "linux-") -> "attention"
      true -> "neutral"
    end
  end

  def platform_badge_color(_), do: "neutral"

  def github_job_url(%{repository: repository, workflow_run_id: run_id, workflow_job_id: job_id})
      when is_binary(repository) and repository != "" and is_integer(run_id) and run_id > 0 and is_integer(job_id) and
             job_id > 0 do
    "https://github.com/#{repository}/actions/runs/#{run_id}/job/#{job_id}"
  end

  def github_job_url(_), do: nil

  def queued_duration_ms(%{enqueued_at: enqueued, claimed_at: claimed}) do
    cond do
      epoch?(enqueued) -> 0
      epoch?(claimed) -> ms_since(enqueued)
      true -> DateTime.diff(claimed, enqueued, :millisecond)
    end
  end

  def run_duration_ms(%{started_at: started, completed_at: completed}) do
    cond do
      epoch?(started) -> 0
      epoch?(completed) -> ms_since(started)
      true -> DateTime.diff(completed, started, :millisecond)
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

  def short_sha(""), do: "–"
  def short_sha(nil), do: "–"
  def short_sha(sha) when is_binary(sha), do: String.slice(sha, 0, 7)
end
