defmodule Tuist.Runners.Workers.PodClaimReconciliationWorker do
  @moduledoc """
  Reconciles Postgres `runner_claims` against the Pods that actually
  exist, releasing capacity held by claims whose Pod is gone.

  ## Why this exists

  A claim is a reservation against an account's concurrency budget, and
  the thing physically holding that capacity is a Pod. Every other
  release path infers the Pod is gone from something else:

    * the `workflow_job.completed` webhook (an edge, keyed on
      `runner_name`, silently releases nothing when GitHub reports no
      runner)
    * the controller's pod-stopped POST (an edge, skipped entirely when
      the reaper deletes the Pod before the lifecycle reconciler
      observes it ending)
    * `StaleClaimsWorker`, keyed on the claim's `lifecycle_state`
    * `OrphanedRunnersWorker`, keyed on the lifecycle row's `status`

  Each covers a slice, and the slices are defined by *how we learned*
  rather than by *what is true*, so a row can be invisible to all of
  them at once. Production had claims stuck for over ten days in exactly
  that hole: the claim said `running` so the `claimed` sweep skipped
  them, the job state said `claimed` so the `running` sweep skipped
  them, and no completion had been recorded.

  This worker asks the only question that does not depend on any of
  that: does the Pod exist? It is level-triggered — it compares desired
  state against observed state and corrects the difference, rather than
  reacting to an event it might never receive. Kubernetes applies the
  same shape to ResourceQuota, where admission is incremental but a
  periodic resync recomputes usage from observed objects and writes the
  correction.

  ## Safety

  The failure mode here is inverted and worse than a leak: releasing a
  claim whose runner is alive lets the account exceed its cap and
  oversubscribe real hosts. A bad cluster read must never do that, so
  every guard below biases toward doing nothing:

    1. **Complete reads only.** Any API error aborts the tick. A
       partial listing is indistinguishable from mass absence.
    2. **Non-empty result.** Zero Pods returned while claims exist is
       treated as a bad read (wrong selector, wrong namespace, empty
       cache), not as an empty fleet.
    3. **Grace window.** Claims younger than `@grace_seconds` are never
       considered — a Pod is labelled just after its claim is inserted
       and the read is eventually consistent.
    4. **Consecutive absence.** A first absence only records
       `pod_missing_since`. Release needs the absence to persist past
       `@confirm_seconds`, so a single unlucky read cannot free a slot,
       and a Pod that reappears resets the clock.
    5. **Bounded blast radius.** At most `@max_releases_per_tick` per
       run, with the overflow reported rather than silently trickled.

  Losing all five leaves the current behaviour (a leak), which is
  survivable. Over-releasing is not, which is why the bias runs this
  way.

  Freeing the slot is only half the job — the workflow_job must be
  claimable again. `Claims.release_pod_missing/2` deletes the claim and
  re-queues the lifecycle row in one transaction, so a release either
  fully returns the job to the queue or does nothing.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Environment
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Telemetry

  require Logger

  # A claim is inserted before its Pod is labelled, and the cluster read
  # is eventually consistent, so young claims are legitimately absent.
  @grace_seconds 600

  # How long an absence must persist before it is believed. Spans several
  # ticks of the 1-minute cron so a transient read cannot clear the bar.
  @confirm_seconds 300

  # Bounds a wrong-but-plausible read that survives the guards above.
  @max_releases_per_tick 25

  @runner_label_selector "tuist.dev/runner=true"

  @impl Oban.Worker
  def perform(_job) do
    if paused?() do
      :ok
    else
      now = DateTime.utc_now()
      grace_threshold = DateTime.add(now, -@grace_seconds, :second)

      case Claims.list_for_pod_reconciliation(grace_threshold) do
        [] -> :ok
        claims -> reconcile(claims, now)
      end
    end
  end

  # Kill switch. This worker deletes rows, and the guards below can only
  # defend against failures we anticipated. Flipping
  # `runner_pod_reconciliation_paused` stops it within a tick, without
  # waiting for a deploy to remove the cron entry.
  defp paused?, do: FunWithFlags.enabled?(:runner_pod_reconciliation_paused)

  defp reconcile(claims, now) do
    case observed_pod_names() do
      {:ok, pod_names} ->
        if MapSet.size(pod_names) == 0 do
          # Guard 2. We hold claims, so the fleet cannot really be empty;
          # far more likely the selector or namespace is wrong, or the
          # apiserver returned an empty page. Acting here would release
          # every claim at once.
          Logger.error("runners: pod reconciliation read returned no Pods while claims exist; skipping",
            claims: length(claims)
          )

          :ok
        else
          apply_observation(claims, pod_names, now)
        end

      {:error, reason} ->
        # Guard 1. A partial or failed read looks exactly like mass
        # absence. Do nothing and let the next tick retry.
        Logger.warning("runners: pod reconciliation cluster read failed; skipping tick",
          reason: inspect(reason)
        )

        :ok
    end
  end

  defp apply_observation(claims, pod_names, now) do
    {present, missing} = Enum.split_with(claims, &MapSet.member?(pod_names, &1.pod_name))

    # Guard 4, first half: a Pod that came back resets its clock, so only
    # uninterrupted absence accumulates toward a release.
    cleared =
      present
      |> Enum.filter(&(&1.pod_missing_since != nil))
      |> Enum.map(& &1.workflow_job_id)
      |> Claims.clear_pods_missing()

    marked =
      missing
      |> Enum.map(& &1.workflow_job_id)
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
      |> Enum.map(& &1.workflow_job_id)

    count = length(released)

    if count > 0 do
      Logger.warning("runners: released claims whose Pod is gone",
        count: count,
        workflow_job_ids: Enum.take(released, 10),
        confirmed_absent_seconds: @confirm_seconds
      )

      :telemetry.execute(
        Telemetry.event_name_recovery(),
        %{count: count},
        %{kind: "pod_missing_claim"}
      )
    end

    # Guard 5's reporting half. A backlog above the cap means either a
    # genuine mass teardown or a read we should not have trusted, and
    # both are worth seeing rather than trickling away silently.
    if eligible > count do
      Logger.warning("runners: pod reconciliation deferred releases past the per-tick cap",
        eligible: eligible,
        released: count,
        cap: @max_releases_per_tick
      )
    end

    count
  end

  # Freeing the slot is only half the job — the workflow_job must be
  # claimable again. `release_pod_missing/2` deletes the claim and
  # re-queues the lifecycle row in one transaction; a terminal row
  # never matches the requeue guard, so a finished job is never
  # resurrected — it just loses its claim.
  defp recover_one(%{workflow_job_id: workflow_job_id, pod_missing_since: handle}) do
    Claims.release_pod_missing(workflow_job_id, handle) == :ok
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
