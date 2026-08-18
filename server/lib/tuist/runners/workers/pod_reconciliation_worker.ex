defmodule Tuist.Runners.Workers.PodReconciliationWorker do
  @moduledoc """
  Reconciles Postgres against the Pods that actually exist, correcting
  both rows a vanished Pod strands: the `runner_claims` row holding its
  slice of the account's concurrency budget, and the `runner_sessions`
  row holding its host.

  ## Why this exists

  Both rows are reservations, and the thing physically holding each one
  is a Pod. Every other release path infers the Pod is gone from
  something else:

    * the `workflow_job.completed` webhook (an edge, keyed on
      `runner_name`, silently releases nothing when GitHub reports no
      runner)
    * the controller's pod-stopped POST (two edges: the pod-lifecycle
      reconciler on the terminal transition, and the reap itself
      immediately before it deletes. Together they cover every Pod the
      controller reaps, but neither fires for a Pod removed by something
      else — node loss, eviction, drain, a manual delete — or for a Pod
      that ended while the controller was restarting)
    * `StaleClaimsWorker`, keyed on the Postgres `lifecycle_state`
    * `OrphanedRunnersWorker`, keyed on the ClickHouse `status`

  Each covers a slice, and the slices are defined by *how we learned*
  rather than by *what is true*, so a row can be invisible to all of
  them at once. Production had claims stuck for over ten days in exactly
  that hole: Postgres said `running` so the `claimed` sweep skipped
  them, ClickHouse said `claimed` so the `running` sweep skipped them,
  and no completion had been recorded. Sessions leaked on the same
  principle but continuously, until the reap was ordered to report before
  deleting: on 2026-08-14, 264 of 1185 sessions never closed, a rate of
  21-25% that held on every fleet and every working day back to at least
  2026-07-07. Each one read to the allocator as an occupied host for six
  hours, so a busy afternoon could withhold more hosts than the fleet
  has. That leak is an ordering bug and is fixed at its source; what is
  left for this worker is the residue no edge can see.

  This worker asks the only question that does not depend on any of
  that: does the Pod exist? It is level-triggered — it compares desired
  state against observed state and corrects the difference, rather than
  reacting to an event it might never receive. Kubernetes applies the
  same shape to ResourceQuota, where admission is incremental but a
  periodic resync recomputes usage from observed objects and writes the
  correction.

  Claims and sessions are corrected from **one** observation rather than
  by two workers polling the same selector a minute apart. They answer
  the same question and only diverge in what they do with the answer,
  and a second reconciler for the same fact is how this family grew in
  the first place.

  ## Claims and sessions are not the same reservation

  A claim is released when its job completes; the session stays open
  through teardown. That trailing window is where the leaked sessions
  sat, so a session needs its own pass rather than riding the claim's.
  The two also carry different risk, which is why only one of them waits
  for a confirmed absence — see Safety below.

  ## Safety

  The failure mode here is inverted and worse than a leak: releasing a
  claim whose runner is alive lets the account exceed its cap and
  oversubscribe real hosts. A bad cluster read must never do that, so
  every guard below biases toward doing nothing. The first three protect
  both corrections off the single read:

    1. **Complete reads only.** Any API error aborts the tick. A
       partial listing is indistinguishable from mass absence.
    2. **Non-empty result.** Zero Pods returned while claims or sessions
       are open is treated as a bad read (wrong selector, wrong
       namespace, empty cache), not as an empty fleet.
    3. **Grace window.** Rows younger than their arm's threshold are
       never considered — a Pod is labelled just after its claim is
       inserted, and a session is written at claim-win before the Pod
       exists to be listed at all.
    4. **Bounded blast radius.** At most `@max_releases_per_tick` claims
       and `@max_closes_per_tick` sessions per run, with the overflow
       reported rather than silently trickled.

  Claims add a fifth: **consecutive absence.** A first absence only
  records `pod_missing_since`; the release needs it to persist past
  `@confirm_seconds`, and a Pod that reappears resets the clock.
  Sessions deliberately do not. `K8sClient.list_pods/2` issues an
  unpaginated GET with no `resourceVersion=0`, so it reads at quorum
  rather than from the watch cache, and the realistic way a live Pod
  leaves this selector — a label change during a rollout — is
  persistent, so waiting would delay that bad close rather than prevent
  it. The consequences differ too: over-releasing a claim oversubscribes
  hosts, while over-closing a session under-bills and dips occupancy
  that the claim side of `RunnerSessions.occupied_counts_per_fleet/0`
  largely still covers.

  Losing these leaves the current behaviour (a leak), which is
  survivable. Over-releasing is not, which is why the bias runs this
  way.

  ## CH before PG

  Freeing the slot is only half the job. A Pod can vanish while its
  ClickHouse row still reads `claimed` or `running`, so releasing the
  Postgres claim first would free the capacity and strand the
  workflow_job permanently: `pick_queued` only selects `queued`, and with
  no claim left no later sweep can recover it. Each release therefore
  writes `queued` to ClickHouse before deleting the row, the same
  ordering `StaleClaimsWorker` follows, and a ClickHouse failure skips
  the claim so the pair is retried intact next tick.

  ## Which `ended_at` a closed session gets

  Closing at the six-hour billing clamp would fix capacity and leave the
  invoice wrong. The clamp is what an unclosed row was *already* being
  charged against, so draining the backlog there is a no-op on billing:
  one account's month-to-date orphans would settle at roughly 36,000
  minutes against about 1,400 minutes of real work. A fresh orphan is
  wrong the other way — it would bill a floor of
  `@session_absence_seconds` whether the job ran for two hours or ninety
  seconds.

  So the session arm resolves its batch against
  `Jobs.terminal_completions/1` first: one ClickHouse query, bounded by
  `@max_closes_per_tick`, returning `completed_at` for the jobs whose
  latest state is terminal. A session that resolves closes at its job's
  real completion; everything else closes at the clamp, which stays the
  right conservative answer when there is no evidence of a real end. See
  `RunnerSessions.close_pod_missing/3` for why the write is
  `GREATEST(started_at, LEAST(completed_at, now, started_at + max_session_lifetime))`
  rather than the completion alone. A ClickHouse failure degrades the
  whole batch to the clamp, so the capacity fix never waits on the
  billing refinement.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Environment
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.RunnerSessions
  alias Tuist.Runners.Telemetry

  require Logger

  # A claim is inserted before its Pod is labelled, and the cluster read
  # is eventually consistent, so young claims are legitimately absent.
  @grace_seconds 600

  # How long a claim's absence must persist before it is believed. Spans
  # several ticks of the 1-minute cron so a transient read cannot clear
  # the bar.
  @confirm_seconds 300

  # Bounds a wrong-but-plausible read that survives the guards above.
  @max_releases_per_tick 25

  # A session is written at claim-win, before the Pod exists to be
  # listed, so anything younger is legitimately absent. Wider than the
  # claim grace because the session arm acts on a single observation.
  @session_absence_seconds 900

  # Bounds the session arm the same way, and paces the first drain of a
  # long-standing backlog.
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

  # Kill switch. This worker deletes and closes rows, and the guards
  # below can only defend against failures we anticipated. Flipping
  # `runner_pod_reconciliation_paused` stops both arms within a tick,
  # without waiting for a deploy to remove the cron entry.
  defp paused?, do: FunWithFlags.enabled?(:runner_pod_reconciliation_paused)

  defp reconcile(claims, sessions, now) do
    case observed_pod_names() do
      {:ok, pod_names} ->
        if MapSet.size(pod_names) == 0 do
          # Guard 2. We hold claims or open sessions, so the fleet cannot
          # really be empty; far more likely the selector or namespace is
          # wrong, or the apiserver returned an empty page. Acting here
          # would release every claim and close every session at once.
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
        # Guard 1. A partial or failed read looks exactly like mass
        # absence. Do nothing and let the next tick retry.
        Logger.warning("runners: pod reconciliation cluster read failed; skipping tick",
          reason: inspect(reason)
        )

        :ok
    end
  end

  defp reconcile_claims([], _pod_names, _now), do: :ok

  defp reconcile_claims(claims, pod_names, now) do
    {present, missing} = Enum.split_with(claims, &MapSet.member?(pod_names, &1.pod_name))

    # Consecutive absence, first half: a Pod that came back resets its
    # clock, so only uninterrupted absence accumulates toward a release.
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

    # Guard 4's reporting half. A backlog above the cap means either a
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

  defp reconcile_sessions([], _pod_names, _now), do: :ok

  defp reconcile_sessions(sessions, pod_names, now) do
    missing = Enum.reject(sessions, &MapSet.member?(pod_names, &1.pod_name))

    # `list_open_for_pod_reconciliation/1` returns oldest first, so a
    # capped batch drains the longest-standing leaks and the rest wait
    # for the next tick.
    batch = Enum.take(missing, @max_closes_per_tick)
    completions = fetch_terminal_completions(batch)
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

  # CH before PG, the contract `Claims.list_stale/1` documents.
  #
  # Freeing the slot is only half the job. A Pod can vanish while its
  # ClickHouse row still reads `claimed` or `running` — the crash window
  # between `mark_running/2` and `Jobs.record_running/2` produces exactly
  # that, and production had rows stuck there for over ten days. Deleting
  # the PG claim first would free the capacity and strand the
  # workflow_job for good: `pick_queued` only selects `queued`, and with
  # no PG row left no later sweep can put it back.
  #
  # `record_queued/1` no-ops when a completion is already recorded, so a
  # finished job is never resurrected — it just loses its claim.
  #
  # A CH failure means skip: the claim stays, the handle stays, and the
  # next tick retries the pair.
  defp recover_one(%{workflow_job_id: workflow_job_id, pod_missing_since: handle}) do
    case safe_record_queued(workflow_job_id) do
      :ok -> Claims.release_pod_missing(workflow_job_id, handle) == :ok
      :error -> false
    end
  end

  defp safe_record_queued(workflow_job_id) do
    Jobs.record_queued(workflow_job_id)
  rescue
    e ->
      Logger.warning("runners: record_queued failed in pod reconciliation; will retry next tick",
        workflow_job_id: workflow_job_id,
        ch_error: Exception.message(e)
      )

      :error
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
