defmodule TuistWeb.RunnerWorkflowRunLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.Runners
  alias Tuist.Runners.Jobs
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.RunnerJobLive
  alias TuistWeb.RunnerWorkflowLive

  @impl true
  def mount(
        %{"workflow_run_id" => run_id_param},
        _session,
        %{assigns: %{selected_account: account, current_user: current_user}} = socket
      ) do
    if Authorization.authorize(:runners_read, current_user, account) != :ok or
         not FeatureFlags.runners_enabled?(account) do
      raise NotFoundError,
            dgettext("dashboard_runners", "The page you are looking for doesn't exist or has been moved.")
    end

    run_id = parse_run_id(run_id_param)
    jobs = if run_id, do: Jobs.jobs_for_run(account.id, run_id), else: []

    # A run with no jobs for this account isn't addressable — 404 rather
    # than render an empty shell.
    if jobs == [] do
      raise NotFoundError,
            dgettext("dashboard_runners", "The page you are looking for doesn't exist or has been moved.")
    end

    representative = hd(jobs)
    status = run_status(jobs)

    head_title =
      "#{RunnerWorkflowLive.display_workflow(representative.workflow_name)} · #{representative.repository} · #{dgettext("dashboard_runners", "Runs")} · #{account.name} · Tuist"

    {:ok,
     socket
     |> assign(:head_title, head_title)
     |> assign(:workflow_run_id, run_id)
     |> assign(:repository, representative.repository)
     |> assign(:workflow_name, representative.workflow_name)
     |> assign(:head_branch, representative.head_branch)
     |> assign(:head_sha, representative.head_sha)
     |> assign(:run_attempt, representative.run_attempt)
     |> assign(:run_status, status)
     |> assign(:jobs, jobs)
     |> assign(:can_cancel_runs, Runners.can_cancel_workflow_runs?(account))}
  end

  @impl true
  def handle_event("cancel_run", _params, socket) do
    %{selected_account: account, current_user: current_user, repository: repository, workflow_run_id: run_id} =
      socket.assigns

    with :ok <- Authorization.authorize(:runners_cancel, current_user, account),
         :ok <- Runners.cancel_workflow_run(account, repository, run_id) do
      {:noreply, put_flash(socket, :info, dgettext("dashboard_runners", "Cancelling the workflow run…"))}
    else
      {:error, :no_installation} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("dashboard_runners", "No GitHub App installation is connected for this account.")
         )}

      {:error, :forbidden} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("dashboard_runners", "Cancelling a run needs the Tuist GitHub App to have write access to Actions.")
         )}

      _ ->
        {:noreply,
         put_flash(socket, :error, dgettext("dashboard_runners", "Couldn't cancel the workflow run. Please try again."))}
    end
  end

  defp parse_run_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> n
      _ -> nil
    end
  end

  defp parse_run_id(_), do: nil

  # Roll the run's jobs up to a single status: any non-completed job
  # keeps the run in progress; otherwise collapse the conclusions.
  defp run_status(jobs) do
    cond do
      Enum.any?(jobs, &(&1.status != "completed")) -> %{status: "in_progress", conclusion: ""}
      Enum.any?(jobs, &(&1.conclusion == "failure")) -> %{status: "completed", conclusion: "failure"}
      Enum.any?(jobs, &(&1.conclusion == "cancelled")) -> %{status: "completed", conclusion: "cancelled"}
      Enum.any?(jobs, &(&1.conclusion == "success")) -> %{status: "completed", conclusion: "success"}
      true -> %{status: "completed", conclusion: "skipped"}
    end
  end

  def run_cancellable?(%{status: "in_progress"}), do: true
  def run_cancellable?(_), do: false

  # Per-job badge: a completed job shows its conclusion, otherwise its
  # lifecycle status. Reuses the workflow page's badge mappings.
  def job_status_badge_props(%{status: "completed", conclusion: conclusion}) when conclusion not in [nil, ""] do
    RunnerWorkflowLive.conclusion_badge_props(conclusion) ||
      RunnerWorkflowLive.status_badge_props("completed")
  end

  def job_status_badge_props(%{status: status}), do: RunnerWorkflowLive.status_badge_props(status)

  @doc """
  Path to the parent named workflow's detail page, or `nil` when the
  run carries no repository / workflow_name.
  """
  def workflow_path(account_name, repository, workflow_name)
      when is_binary(repository) and is_binary(workflow_name) and workflow_name != "" do
    case String.split(repository, "/", parts: 2) do
      [owner, name] when owner != "" and name != "" ->
        encoded = URI.encode(workflow_name, &URI.char_unreserved?/1)
        "/#{account_name}/runners/workflows/#{owner}/#{name}/#{encoded}"

      _ ->
        nil
    end
  end

  def workflow_path(_, _, _), do: nil

  def job_path(account_name, job), do: RunnerJobLive.path(account_name, job)

  def github_run_url(repository, run_id), do: RunnerWorkflowLive.github_run_url(repository, run_id)

  def job_duration_ms(job), do: RunnerWorkflowLive.duration_ms(job)
end
