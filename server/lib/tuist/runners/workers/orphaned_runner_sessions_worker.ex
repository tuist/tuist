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
    3. **Grace window.** Sessions younger than `@grace_seconds` are
       never considered — the row is written before the Pod is labelled
       and the read is eventually consistent.
    4. **Consecutive absence.** A first absence only records
       `pod_missing_since`; the close needs the absence to persist past
       `@confirm_seconds`, and a Pod that reappears resets the clock.
    5. **Bounded blast radius.** At most `@max_closes_per_tick` per run,
       with the overflow reported rather than silently trickled.

  ## Why `ended_at` is the billing clamp

  `RunnerSessions.close_pod_missing/3` writes
  `LEAST(now, started_at + max_session_lifetime)` — the instant
  `Tuist.Runners.Billing` was already clamping the open row to. The close
  is therefore billing-neutral and only changes what the autoscaler sees.
  It also means the backlog of already-leaked rows can be drained by this
  worker rather than by a one-off script: each one closes at the bound it
  was already charged against.

  For a fresh orphan the same expression resolves to `now`, overstating
  the window by at most one tick. That is the only bound still provable
  once the Pod is gone, and it errs in the direction that cannot
  under-bill a customer who really did hold a runner.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Environment
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.RunnerSessions
  alias Tuist.Runners.Telemetry

  require Logger

  # A session is inserted before its Pod is labelled, and the cluster
  # read is eventually consistent, so young sessions are legitimately
  # absent. Matches `PodClaimReconciliationWorker`.
  @grace_seconds 600

  # How long an absence must persist before it is believed. Spans
  # several ticks of the 1-minute cron so a transient read cannot clear
  # the bar.
  @confirm_seconds 300

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
      grace_threshold = DateTime.add(now, -@grace_seconds, :second)

      case RunnerSessions.list_open_for_pod_reconciliation(grace_threshold) do
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
    {present, missing} = Enum.split_with(sessions, &MapSet.member?(pod_names, &1.pod_name))

    # Guard 4, first half: a Pod that came back resets its clock, so only
    # uninterrupted absence accumulates toward a close.
    cleared =
      present
      |> Enum.filter(&(&1.pod_missing_since != nil))
      |> Enum.map(& &1.id)
      |> RunnerSessions.clear_pods_missing()

    marked =
      missing
      |> Enum.map(& &1.id)
      |> RunnerSessions.mark_pods_missing(now)

    closed = close_confirmed(now)

    if cleared > 0 or marked > 0 or closed > 0 do
      Logger.info("runners: reconciled open sessions against observed Pods",
        observed_pods: MapSet.size(pod_names),
        sessions: length(sessions),
        missing: length(missing),
        newly_marked: marked,
        recovered: cleared,
        closed: closed
      )
    end

    :ok
  end

  defp close_confirmed(now) do
    confirmed_before = DateTime.add(now, -@confirm_seconds, :second)
    eligible = RunnerSessions.count_pods_missing_since(confirmed_before)

    closed =
      confirmed_before
      |> RunnerSessions.list_pods_missing_since(@max_closes_per_tick)
      |> Enum.filter(&(RunnerSessions.close_pod_missing(&1.id, &1.pod_missing_since, now) == :ok))

    count = length(closed)

    if count > 0 do
      Logger.warning("runners: closed runner sessions whose Pod is gone",
        count: count,
        pods: closed |> Enum.map(& &1.pod_name) |> Enum.take(10),
        confirmed_absent_seconds: @confirm_seconds
      )

      :telemetry.execute(
        Telemetry.event_name_recovery(),
        %{count: count},
        %{kind: "orphaned_runner_session"}
      )
    end

    # Guard 5's reporting half. A backlog above the cap means either a
    # genuine mass teardown or a read we should not have trusted, and
    # both are worth seeing rather than trickling away silently.
    if eligible > count do
      Logger.warning("runners: session reconciliation deferred closes past the per-tick cap",
        eligible: eligible,
        closed: count,
        cap: @max_closes_per_tick
      )
    end

    count
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
