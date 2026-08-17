defmodule Tuist.Runners.Workers.OrphanedRunnerSessionsWorker do
  @moduledoc """
  Closes `runner_sessions` rows whose Pod no longer exists.

  ## Why this exists

  A session is opened at claim-win and closed by the controller's
  pod-stopped report. That report is an edge, and every edge can be
  missed: the reap can collect a Pod before the lifecycle reconciler
  drains its terminal transition, and a controller restart loses every
  Pod that ended during the downtime because the informer only replays
  objects that still exist. `PodLifecycleReconciler` now reports a
  vanished Pod on the next event it does see, which covers the race but
  not the restart, and neither covers a Pod deleted out-of-band.

  What made the residue expensive is that an open session is not only a
  billing record. `RunnerSessions.occupied_counts_per_fleet/0` counts it
  as an occupied host, so a leaked row withholds a Mac mini from every
  sibling pool for the full six hours of the safety clamp. Production
  reached seventeen phantom sessions on one fleet against nine physical
  minis, which reads to the allocator as a saturated fleet and starves
  every pool sharing those hosts.

  So this worker asks the question none of the edges depend on: does the
  Pod exist? It is level-triggered — the same shape as
  `PodClaimReconciliationWorker`, which reconciles `runner_claims`
  against the same observed Pod set. Sessions need their own pass
  because they outlive claims: the claim is released on completion while
  the session stays open through teardown, which is exactly the window
  the leaked rows sat in.

  ## Safety

  Closing a live runner's session under-bills the customer and hides
  real occupancy, so every guard biases toward doing nothing:

    1. **Complete reads only.** Any API error aborts the tick. A partial
       listing is indistinguishable from mass absence.
    2. **Non-empty result.** Zero Pods returned while sessions are open
       is treated as a bad read (wrong selector, wrong namespace, empty
       cache), not as an empty fleet.
    3. **Absence window.** Sessions younger than
       `@absence_threshold_seconds` are never considered — the row is
       written at claim-win, before the Pod exists to be listed.
    4. **Bounded blast radius.** At most `@max_closes_per_tick` per run,
       oldest first, with the overflow reported rather than silently
       trickled.

  There is deliberately no consecutive-absence confirmation, unlike
  `PodClaimReconciliationWorker`'s `pod_missing_since` clock. That guard
  defends against a live Pod being transiently missing from an otherwise
  good read, and it does not pay for itself here. `K8sClient.list_pods/2`
  issues an unpaginated GET with no `resourceVersion=0`, so it is a
  quorum read rather than the watch cache; the realistic way a live Pod
  leaves this selector is a label change during a rollout, which is
  persistent, so requiring consecutive absence would delay that bad close
  rather than prevent it. The consequences also differ: over-releasing a
  claim oversubscribes real hosts, while over-closing a session
  under-bills and dips occupancy that the claim side of
  `RunnerSessions.occupied_counts_per_fleet/0` largely still covers.

  ## Which `ended_at` gets written

  Closing at the six-hour billing clamp would fix capacity and leave the
  invoice wrong. The clamp is what an unclosed row was *already* being
  charged against, so draining the backlog there is a no-op on billing:
  one account's month-to-date orphans would settle at roughly 36,000
  minutes against about 1,400 minutes of real work. A fresh orphan is
  wrong the other way — it would bill a floor of
  `@absence_threshold_seconds` whether the job ran for two hours or
  ninety seconds.

  So each tick resolves the batch against `Jobs.terminal_completions/1`
  first: one ClickHouse query, bounded by `@max_closes_per_tick`,
  returning `completed_at` for the jobs whose latest state is terminal.
  A session that resolves closes at its job's real completion;
  everything else closes at the clamp, which stays the right
  conservative answer when there is no evidence of a real end.

  Both directions are bounded — see
  `RunnerSessions.close_pod_missing/3` for why the write is
  `GREATEST(started_at, LEAST(completed_at, now, started_at + max_session_lifetime))`
  rather than the completion alone. A ClickHouse failure degrades the
  whole batch to the clamp, so the capacity fix never waits on the
  billing refinement.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Environment
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.RunnerSessions
  alias Tuist.Runners.Telemetry

  require Logger

  # How old a session must be before its Pod's absence means anything.
  # The row is written at claim-win, before the Pod exists to be listed,
  # so anything younger is legitimately absent. Sized to span several
  # ticks of the 1-minute cron.
  @absence_threshold_seconds 900

  # Bounds a wrong-but-plausible read that survives the guards above,
  # and paces the first drain of a long-standing backlog.
  @max_closes_per_tick 100

  @runner_label_selector "tuist.dev/runner=true"

  @impl Oban.Worker
  def perform(_job) do
    if paused?() do
      :ok
    else
      now = DateTime.utc_now()
      threshold = DateTime.add(now, -@absence_threshold_seconds, :second)

      case RunnerSessions.list_open_for_pod_reconciliation(threshold) do
        [] -> :ok
        sessions -> reconcile(sessions, now)
      end
    end
  end

  # Kill switch, shared with the claim reconciler: both act on the same
  # observation, so a cluster read we should not have trusted is a reason
  # to stop both within a tick rather than wait for a deploy.
  defp paused?, do: FunWithFlags.enabled?(:runner_pod_reconciliation_paused)

  defp reconcile(sessions, now) do
    case observed_pod_names() do
      {:ok, pod_names} ->
        if MapSet.size(pod_names) == 0 do
          # Guard 2. Sessions are open, so the fleet cannot really be
          # empty; far more likely the selector or namespace is wrong, or
          # the apiserver returned an empty page. Acting here would close
          # every session at once.
          Logger.error("runners: session reconciliation read returned no Pods while sessions are open; skipping",
            sessions: length(sessions)
          )

          :ok
        else
          apply_observation(sessions, pod_names, now)
        end

      {:error, reason} ->
        # Guard 1. A partial or failed read looks exactly like mass
        # absence. Do nothing and let the next tick retry.
        Logger.warning("runners: session reconciliation cluster read failed; skipping tick",
          reason: inspect(reason)
        )

        :ok
    end
  end

  defp apply_observation(sessions, pod_names, now) do
    missing = Enum.reject(sessions, &MapSet.member?(pod_names, &1.pod_name))

    # Guard 4. `list_open_for_pod_reconciliation/1` returns oldest first,
    # so a capped batch drains the longest-standing leaks and the rest
    # wait for the next tick.
    batch = Enum.take(missing, @max_closes_per_tick)
    completions = fetch_terminal_completions(batch)
    closed = Enum.filter(batch, &close_one(&1, completions, now))
    count = length(closed)

    if count > 0 do
      Logger.warning("runners: closed runner sessions whose Pod is gone",
        count: count,
        observed_pods: MapSet.size(pod_names),
        sessions: length(sessions),
        pods: closed |> Enum.map(& &1.pod_name) |> Enum.take(10),
        absent_after_seconds: @absence_threshold_seconds
      )

      :telemetry.execute(
        Telemetry.event_name_recovery(),
        %{count: count},
        %{kind: "orphaned_runner_session"}
      )
    end

    # Guard 4's reporting half. A backlog above the cap means either a
    # genuine mass teardown or a read we should not have trusted, and
    # both are worth seeing rather than trickling away silently.
    if length(missing) > count do
      Logger.warning("runners: session reconciliation deferred closes past the per-tick cap",
        eligible: length(missing),
        closed: count,
        cap: @max_closes_per_tick
      )
    end

    :ok
  end

  defp close_one(session, completions, now) do
    RunnerSessions.close_pod_missing(session.id, now, completed_at: completed_at_for(session, completions)) == :ok
  end

  # `executed_workflow_job_id` outranks the claim-time `workflow_job_id`:
  # a runner can be handed a sibling's job, and it is the job GitHub
  # actually ran — the one whose completion released the Pod — that
  # dates the session's end. `nil` falls through both lookups and the
  # close reverts to the billing clamp.
  defp completed_at_for(session, completions) do
    Map.get(completions, session.executed_workflow_job_id) ||
      Map.get(completions, session.workflow_job_id)
  end

  # One ClickHouse query per tick, bounded by `@max_closes_per_tick`.
  # A failure here must not block the capacity fix, so it degrades to an
  # empty map and every session in the batch closes at the billing clamp
  # exactly as it would have before completions were consulted.
  defp fetch_terminal_completions([]), do: %{}

  defp fetch_terminal_completions(candidates) do
    candidates
    |> Enum.flat_map(&[&1.executed_workflow_job_id, &1.workflow_job_id])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Jobs.terminal_completions()
  rescue
    e ->
      Logger.warning("runners: terminal completion lookup failed; closing at the billing clamp",
        ch_error: Exception.message(e)
      )

      %{}
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
