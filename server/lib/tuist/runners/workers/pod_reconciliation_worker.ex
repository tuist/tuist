defmodule Tuist.Runners.Workers.PodReconciliationWorker do
  @moduledoc """
  Failsafe. Releases `runner_claims` and closes `runner_sessions` whose
  Pod no longer exists.

  Both are reservations held by a Pod, and both are normally cleared on
  an edge: `reapRunner` reports the stop before it deletes, the
  `workflow_job.completed` webhook releases the claim, and
  `StaleClaimsWorker` / `OrphanedRunnersWorker` sweep their own slices.
  Those edges cover every Pod the controller reaps and nothing removed
  by anyone else — node loss, eviction, drain, a manual delete — where
  there is no event left to hook.

  So this asks the one question that does not depend on how we learned:
  does the Pod exist? Level-triggered, one cluster read per tick, both
  corrections off it.

  A sustained `tuist_runners_recovery_count{kind}` means an edge is
  broken. Fix it there, not here.

  ## Safety

  Over-releasing is worse than leaking: freeing a claim whose runner is
  alive lets the account exceed its cap and oversubscribe real hosts.
  Every guard biases toward doing nothing.

    * Any API error, or an empty Pod list while rows are open, aborts
      the tick — a partial read is indistinguishable from mass absence.
    * Rows younger than their arm's threshold are skipped, keeping both
      arms clear of the dispatch and teardown churn. Neither waits for
      the Pod to appear — it is created and polling before either row is
      written.
    * Per-tick caps bound a wrong-but-plausible read, overflow logged.
    * Claims additionally require absence across consecutive ticks
      (`pod_missing_since`). Sessions do not: `list_pods/2` reads at
      quorum, and the realistic way a live Pod leaves this selector is a
      label change mid-rollout, which is persistent — waiting would
      delay a bad close rather than prevent one.

  ## Releasing is only half the job

  The workflow_job also has to become claimable again.
  `Claims.release_pod_missing/2` deletes the claim and re-queues the
  lifecycle row in one transaction, so a release either fully returns the
  job to the queue or does nothing.

  Closed sessions resolve their `ended_at` from the job's terminal
  completion where there is one; see `RunnerSessions.close_pod_missing/3`.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Environment
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.Claims
  alias Tuist.Runners.RunnerSessions
  alias Tuist.Runners.Telemetry
  alias Tuist.Runners.WorkflowJobs

  require Logger

  @grace_seconds 600
  @confirm_seconds 300
  @max_releases_per_tick 25

  # Wider than the claim grace: the session arm acts on one observation.
  @session_absence_seconds 900
  @max_closes_per_tick 100

  @runner_label_selector "tuist.dev/runner=true"

  @impl Oban.Worker
  def perform(_job) do
    if paused?() do
      :ok
    else
      now = DateTime.utc_now()

      claims = Claims.list_for_pod_reconciliation(DateTime.add(now, -@grace_seconds, :second))
      sessions = RunnerSessions.list_open_for_pod_reconciliation(DateTime.add(now, -@session_absence_seconds, :second))

      if claims == [] and sessions == [] do
        :ok
      else
        reconcile(claims, sessions, now)
      end
    end
  end

  # Kill switch for both arms, without waiting for a deploy to pull the
  # cron entry.
  defp paused?, do: FunWithFlags.enabled?(:runner_pod_reconciliation_paused)

  defp reconcile(claims, sessions, now) do
    case observed_pod_names() do
      {:ok, pod_names} ->
        if MapSet.size(pod_names) == 0 do
          # Rows are open, so the fleet cannot really be empty: wrong
          # selector, wrong namespace, or an empty page.
          Logger.error("runners: pod reconciliation read returned no Pods while rows are open; skipping",
            claims: length(claims),
            sessions: length(sessions)
          )

          :ok
        else
          reconcile_claims(claims, pod_names, now)
          reconcile_sessions(sessions, pod_names, now)
          :ok
        end

      {:error, reason} ->
        Logger.warning("runners: pod reconciliation cluster read failed; skipping tick",
          reason: inspect(reason)
        )

        :ok
    end
  end

  defp reconcile_claims([], _pod_names, _now), do: :ok

  defp reconcile_claims(claims, pod_names, now) do
    {present, missing} = Enum.split_with(claims, &MapSet.member?(pod_names, &1.pod_name))

    # A Pod that came back resets its clock.
    cleared =
      present
      |> Enum.filter(&(&1.pod_missing_since != nil))
      |> Enum.map(& &1.pod_name)
      |> Claims.clear_pods_missing()

    marked =
      missing
      |> Enum.map(& &1.pod_name)
      |> Claims.mark_pods_missing(now)

    released = release_confirmed(now)

    if cleared > 0 or marked > 0 or released > 0 do
      Logger.info("runners: reconciled claims against observed Pods",
        observed_pods: MapSet.size(pod_names),
        claims: length(claims),
        missing: length(missing),
        newly_marked: marked,
        recovered: cleared,
        released: released
      )
    end

    :ok
  end

  defp release_confirmed(now) do
    confirmed_before = DateTime.add(now, -@confirm_seconds, :second)
    eligible = Claims.count_pods_missing_since(confirmed_before)

    released =
      confirmed_before
      |> Claims.list_pods_missing_since(@max_releases_per_tick)
      |> Enum.filter(&recover_one/1)
      |> Enum.map(& &1.pod_name)

    count = length(released)

    if count > 0 do
      Logger.warning("runners: released claims whose Pod is gone",
        count: count,
        pods: Enum.take(released, 10),
        confirmed_absent_seconds: @confirm_seconds
      )

      :telemetry.execute(
        Telemetry.event_name_recovery(),
        %{count: count},
        %{kind: "pod_missing_claim"}
      )
    end

    # A backlog past the cap is either a mass teardown or a read we
    # should not have trusted. Both are worth seeing.
    if eligible > count do
      Logger.warning("runners: pod reconciliation deferred releases past the per-tick cap",
        eligible: eligible,
        released: count,
        cap: @max_releases_per_tick
      )
    end

    count
  end

  defp reconcile_sessions([], _pod_names, _now), do: :ok

  defp reconcile_sessions(sessions, pod_names, now) do
    missing = Enum.reject(sessions, &MapSet.member?(pod_names, &1.pod_name))

    # Oldest first, so a capped batch drains the worst leaks.
    batch = Enum.take(missing, @max_closes_per_tick)
    completions = terminal_completions(batch)
    closed = Enum.filter(batch, &close_session(&1, completions, now))
    count = length(closed)

    if count > 0 do
      Logger.warning("runners: closed runner sessions whose Pod is gone",
        count: count,
        observed_pods: MapSet.size(pod_names),
        sessions: length(sessions),
        pods: closed |> Enum.map(& &1.pod_name) |> Enum.take(10),
        absent_after_seconds: @session_absence_seconds
      )

      :telemetry.execute(
        Telemetry.event_name_recovery(),
        %{count: count},
        %{kind: "orphaned_runner_session"}
      )
    end

    if length(missing) > count do
      Logger.warning("runners: pod reconciliation deferred session closes past the per-tick cap",
        eligible: length(missing),
        closed: count,
        cap: @max_closes_per_tick
      )
    end

    :ok
  end

  defp close_session(session, completions, now) do
    RunnerSessions.close_pod_missing(session.id, now, completed_at: completed_at_for(session, completions)) == :ok
  end

  # The job GitHub actually ran outranks the one the claim was minted
  # for; its completion is what released the Pod. `nil` falls through to
  # the billing clamp.
  defp completed_at_for(session, completions) do
    Map.get(completions, session.executed_workflow_job_id) ||
      Map.get(completions, session.workflow_job_id)
  end

  # Freeing the slot is only half the job — the workflow_job must be
  # claimable again. `release_pod_missing/2` deletes the claim and
  # re-queues the lifecycle row in one transaction; a terminal row never
  # matches the requeue guard, so a finished job is never resurrected. A
  # claim whose job was displaced onto another runner has no row left to
  # re-queue — it went back to the queue when GitHub reported the
  # displacement — and only its slot is freed here.
  defp recover_one(%{pod_name: pod_name, pod_missing_since: handle}) do
    Claims.release_pod_missing(pod_name, handle) == :ok
  end

  defp terminal_completions([]), do: %{}

  defp terminal_completions(candidates) do
    candidates
    |> Enum.flat_map(&[&1.executed_workflow_job_id, &1.workflow_job_id])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> WorkflowJobs.terminal_completions()
  end

  defp observed_pod_names do
    case K8sClient.list_pods(Environment.runners_namespace(), @runner_label_selector) do
      {:ok, items} ->
        {:ok,
         items
         |> Enum.map(&get_in(&1, ["metadata", "name"]))
         |> Enum.reject(&is_nil/1)
         |> MapSet.new()}

      {:error, _} = error ->
        error
    end
  end
end
