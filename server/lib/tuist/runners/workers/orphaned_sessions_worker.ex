defmodule Tuist.Runners.Workers.OrphanedSessionsWorker do
  @moduledoc """
  Closes `runner_sessions` rows the runners-controller never
  reported stopped, using GitHub's terminal timestamp for the job
  the Pod actually ran.

  ## The leak this recovers

  A session has exactly one close path: the runners-controller's
  `PodLifecycleReconciler` POSTs `/api/internal/runners/pods/stopped`
  when it observes a Pod in a terminal phase. When the Pod leaves
  the apiserver before that reconcile lands — reap race, controller
  restart, dropped watch event — the reconciler's `IsNotFound`
  branch has no `finishedAt` to send and gives up.

  Nothing else ever closed the row. `OrphanedRunnersWorker` recovers
  `runner_jobs`, `StaleClaimsWorker` recovers `runner_claims`;
  neither touches `runner_sessions`. The session stayed open
  forever and `Tuist.Runners.Billing` fell through to its
  `@max_session_lifetime_seconds` clamp, billing the full safety
  bound for a Pod that had been gone for weeks — observed at 360
  billed minutes against jobs that really ran for 1.5.

  ## How it recovers

    1. List open sessions older than `@grace_seconds` (cheap
       Postgres prefilter; a session younger than the grace period
       cannot have a job that finished before it).
    2. Resolve each one's job in ClickHouse via
       `Jobs.terminal_completions/1`, preferring
       `executed_workflow_job_id` — the job GitHub proved ran on
       this runner — over the claim-time `workflow_job_id`.
    3. Close every session whose job reached `completed` more than
       `@grace_seconds` ago, at that `completed_at`.

  Sessions whose job is absent from ClickHouse, or still in
  flight, are left open on purpose. "Still running" is
  indistinguishable here from "genuinely long build", and real
  six-hour builds exist on these fleets — closing them on a
  guess would under-bill live work. Those rows stay covered by the
  billing clamp, and the job-side recovery workers drive the
  underlying `runner_jobs` row to a terminal state, at which point
  the next tick of this worker closes the session properly.

  ## Why a grace period, and why it is generous

  The controller's report is the authoritative close: it carries
  `containerStatuses[].state.terminated.finishedAt`, the moment the
  runner process exited, and it accounts for the post-job window
  where the Pod is still uploading caches and tearing down —
  occupancy the customer is legitimately billed for.

  This worker's `completed_at` is a proxy that ends at the job
  boundary and misses that tail. Waiting `@grace_seconds` past the
  job's completion means the normal path (which lands within
  seconds) always wins the race, and this only fires once the
  controller has demonstrably failed to report. On the fleets
  measured, the tail is worth seconds — closed sessions summed to
  306.9 minutes against 304.3 minutes of job time over the same
  window — so resolving to `completed_at` is a rounding error in
  the under-bill direction, which is the direction this subsystem
  always errs.

  ## Bounded work per tick

  `@batch_limit` caps one tick's Postgres reads, ClickHouse lookup
  width, and writes. Oldest sessions are resolved first, so a
  backlog drains from the most expensive end. At a one-minute
  cadence the steady state is zero candidates.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Runners.Jobs
  alias Tuist.Runners.RunnerSessions
  alias Tuist.Runners.Telemetry

  require Logger

  @grace_seconds 600
  @batch_limit 500

  @impl Oban.Worker
  def perform(_job) do
    threshold = DateTime.add(DateTime.utc_now(), -@grace_seconds, :second)

    case RunnerSessions.list_open_before(threshold, @batch_limit) do
      [] ->
        :ok

      candidates ->
        candidates |> resolve(threshold) |> close_all()
    end
  end

  # Pairs each candidate session with the terminal `completed_at` of
  # the job it ran, dropping the ones ClickHouse can't yet answer for.
  defp resolve(candidates, threshold) do
    completions =
      candidates
      |> Enum.map(&job_id/1)
      |> Enum.uniq()
      |> Jobs.terminal_completions()

    candidates
    |> Enum.flat_map(fn session ->
      case Map.get(completions, job_id(session)) do
        %DateTime{} = completed_at -> [{session, completed_at}]
        _ -> []
      end
    end)
    |> Enum.filter(fn {_session, completed_at} -> DateTime.before?(completed_at, threshold) end)
  end

  # `executed_workflow_job_id` is GitHub's proof of what this runner
  # actually ran, learned from the `in_progress` / `completed`
  # webhook. It only diverges from the claim-time `workflow_job_id`
  # when the runner picked up a different job than the one it was
  # dispatched for, and in that case the executed job is the one
  # whose completion released the Pod.
  defp job_id(%{executed_workflow_job_id: executed}) when is_integer(executed) and executed > 0, do: executed
  defp job_id(%{workflow_job_id: workflow_job_id}), do: workflow_job_id

  defp close_all([]), do: :ok

  defp close_all(resolved) do
    closed =
      Enum.count(resolved, fn {session, completed_at} ->
        match?({:ok, %_{}}, RunnerSessions.close_by_id(session.id, completed_at))
      end)

    if closed > 0 do
      Logger.warning("runners: closed orphaned billing sessions",
        count: closed,
        grace_seconds: @grace_seconds
      )

      :telemetry.execute(
        Telemetry.event_name_recovery(),
        %{count: closed},
        %{kind: "orphaned_session"}
      )
    end

    :ok
  end
end
