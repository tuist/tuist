defmodule Tuist.Runners.Workers.ExecutionLookupWorker do
  @moduledoc """
  Reads from GitHub's API which job is running on an open session's runner
  and records it as if its `workflow_job.in_progress` webhook had arrived.

  Cache volume allocation needs that binding before it can scope a volume,
  and the host agent waits 30 seconds for it. GitHub normally delivers
  `in_progress` within seconds, but its delivery can fall minutes behind
  while `queued` keeps arriving on time. Allocation enqueues this worker for
  a session still awaiting its binding, and the agent's next retry finds it.

  GitHub places a job on any runner whose labels match, so the job a runner
  executes is often not the one its Pod was minted for, nor in the same
  workflow run. The lookup lists the jobs of the minted job's run first,
  then of the account's other active runs in the same fleet, most recently
  queued first, and binds the first job GitHub names this runner on. GitHub
  names the runner when it assigns the job, and its job status can still read
  `queued` for minutes after the job started, so a `queued` job carrying this
  runner's name binds as well as an `in_progress` one. A later `in_progress`
  delivery for the same pair is a no-op.
  """
  use Oban.Worker,
    queue: :webhooks,
    max_attempts: 1,
    unique: [period: 10, keys: [:session_id]]

  import Ecto.Query

  alias Tuist.GitHub.Client
  alias Tuist.Repo
  alias Tuist.Runners.Dispatch
  alias Tuist.Runners.RunnerSession
  alias Tuist.Runners.WorkflowJob
  alias Tuist.VCS

  require Logger

  @max_runs 10
  @active_window_seconds 6 * 60 * 60

  def enqueue(%RunnerSession{id: session_id}) do
    %{session_id: session_id} |> new() |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"session_id" => session_id}}) do
    with %RunnerSession{ended_at: nil, executed_workflow_job_id: nil, runner_name: runner_name} = session
         when runner_name != "" <- Repo.get(RunnerSession, session_id),
         %WorkflowJob{provider: "github"} = minted <-
           Repo.get_by(WorkflowJob, workflow_job_id: session.workflow_job_id, account_id: session.account_id),
         {:ok, installation} <- VCS.get_github_app_installation_for_account(session.account_id) do
      session
      |> candidate_runs(minted)
      |> Enum.find_value(&executed_job_id(installation, &1, runner_name))
      |> record(session)
    end

    :ok
  end

  defp candidate_runs(%RunnerSession{} = session, %WorkflowJob{} = minted) do
    cutoff = DateTime.add(DateTime.utc_now(), -@active_window_seconds, :second)

    active =
      Repo.all(
        from(j in WorkflowJob,
          where:
            j.account_id == ^session.account_id and j.provider == "github" and j.fleet_name == ^session.fleet_name and
              j.status in ["queued", "claimed", "running"] and j.enqueued_at > ^cutoff,
          group_by: [j.repository, j.workflow_run_id],
          order_by: [desc: max(j.enqueued_at)],
          limit: @max_runs,
          select: {j.repository, j.workflow_run_id}
        )
      )

    [{minted.repository, minted.workflow_run_id} | active]
    |> Enum.uniq()
    |> Enum.take(@max_runs)
  end

  defp executed_job_id(installation, {repository, run_id}, runner_name) do
    case Client.list_workflow_run_jobs(installation, repository, run_id) do
      {:ok, jobs} ->
        Enum.find_value(jobs, fn
          %{id: id, status: status, runner_name: ^runner_name} when status in ["in_progress", "queued"] -> {id, status}
          _ -> nil
        end)

      {:error, reason} ->
        Logger.warning("runners: execution lookup failed to list jobs of run #{run_id}",
          repository: repository,
          reason: inspect(reason)
        )

        nil
    end
  end

  # GitHub reports the job a runner picked up late, by webhook and API alike, so
  # a miss here means the host may give up before the binding arrives. The job
  # logged is the one the runner was minted for.
  defp record(nil, %RunnerSession{} = session) do
    Logger.info("runners: execution lookup found no job GitHub reports running on this runner",
      runner_name: session.runner_name,
      workflow_job_id: session.workflow_job_id
    )
  end

  defp record({executed_workflow_job_id, github_status}, %RunnerSession{} = session) do
    outcome = Dispatch.record_execution(session.runner_name, executed_workflow_job_id, session.account_id)

    Logger.info("runners: recorded execution from GitHub API (#{inspect(outcome)}, GitHub status #{github_status})",
      runner_name: session.runner_name,
      workflow_job_id: executed_workflow_job_id
    )
  end
end
