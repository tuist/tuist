defmodule Tuist.Runners.Workers.OrphanedStampedPodsWorker do
  @moduledoc """
  Reaps runner Pods that carry an owner stamp
  (`tuist.dev/runner-pool-owner`) but have no live Postgres
  `runner_claims` row — "stamped in Kubernetes, unclaimed in the
  database."

  ## Why this exists

  The dispatch path stamps the owner label on a polling Pod the
  instant it wins a claim (`Tuist.Runners.stamp_owner_label/3`),
  *before* minting the JIT. That label is what the runner-pool
  reconciler reads to decide a Pod is busy: it only scales down
  *idle* (un-stamped) Pods, never owner-stamped ones, so a stamped
  Pod survives every reconcile.

  The claim, though, can be released without the Pod ever running a
  job or reaching a terminal phase:

    * `serve_claim/5` stamps the label, then mint/mark-running
      fails (GitHub mint blip, ClickHouse hiccup) and
      `release_safely/3` deletes the PG claim — but not the label;
    * the server is SIGTERM'd mid-dispatch (a deploy) after the
      stamp but before `mark_running`, and `StaleClaimsWorker`
      later reaps the orphaned `claimed` row — but not the Pod;
    * the runner agent never registers and `OrphanedRunnersWorker`
      releases the `running` claim — but not the Pod.

  In every case the Pod is left Running with a stale owner label.
  The reconciler can't scale it down (it isn't idle), the recovery
  workers only touch the database, and the Pod never exits — it
  never received a JIT, so it never ran `run.sh`. It poll-loops
  forever, and on Kata each Pod reserves its full RAM 1:1, so a
  handful starve a node and wedge the whole fleet. A single deploy
  can batch-leak the entire warm pool.

  Because `Claims.attempt/5` INSERTs the claim *before*
  `stamp_owner_label/3` runs, an owner-stamped Pod should *always*
  have a matching claim. A stamped Pod with no claim is therefore
  unambiguously a leak — there is no legitimate transient state.
  This worker reconciles Kubernetes against the claim table (which
  the reconciler can't read) and deletes the Pod **and its
  same-named ServiceAccount** (`Client.delete_runner/2` — Pod and
  SA are RunnerPool siblings, so deleting the Pod alone orphans the
  SA), letting the reconciler boot a fresh, live replacement.

  ## Race-safety

  Pods are listed *before* claims. A Pod claimed after the Pod list
  is taken is absent from the snapshot and never considered; a Pod
  in the snapshot whose claim shows up in the (later) claim read is
  protected. The only residual is a Pod whose job completed inside
  the read window — reaping a just-finished Pod is harmless (it is
  exiting anyway, and the delete is idempotent). A `@grace_seconds`
  floor on Pod age is belt-and-suspenders against clock skew and
  keeps brand-new Pods out of scope.

  ## Live-execution guard

  The stamp-then-no-claim signature was treated as unambiguous proof
  of a wedge above — "an owner-stamped Pod should always have a
  matching claim." That invariant breaks if anything releases the
  PG claim *after* dispatch already delivered the JIT to the Pod
  and the runner started executing a job. `release_safely/3` is the
  documented trigger: it fires from `serve_claim/5`'s `with`-else
  on any post-stamp error (mint blip, `mark_running` PG error,
  `record_running_safe` CH hiccup). The dispatch fails closed and
  the JIT never reaches the Pod, so reaping is correct. But any
  *other* path that reaches `Claims.release`/`Claims.complete`
  while the runner is mid-job (a stale webhook, an orphan-worker
  false positive, future code that touches the claim table) would
  surface here as "stamped, no claim" and force-delete a live
  customer Pod — observable from GitHub's side as a runner that
  "lost communication with the server."

  Two independent signals shield Pods that are actually executing,
  layered for shape coverage:

  1. **Open `RunnerSession`** (shape-independent). `open/1` is
     called on the success branch of `serve_claim/5`, AFTER every
     step that could trigger `release_safely/3` (mint_jit,
     `mark_running`, `record_running_safe`). An open session is
     therefore proof that the full dispatch committed — the JIT was
     returned to the Pod and the runner is or was running a
     customer job. Sessions are closed only by the controller's
     `PodLifecycleReconciler` reporting `pods/stopped` once the
     Pod actually stops. So a live build always has an open
     session, regardless of whether the Pod is Linux or macOS.

  2. **Linux `runner` container started/terminated** (Linux only).
     In the split-container shape the `runner` container is gated
     behind the `poller` init container: it reaches `started=true`
     only once the poller successfully claimed AND staged a JIT.
     This catches the post-job cleanup window where the session
     has been closed (controller already reported `pods/stopped`)
     but the Pod has not yet been reaped by the Pool reconciler —
     `state.terminated` is set, and we defer to the reconciler so
     it can log the runner's exit code via `#11109` instead of
     racing it with a silent reap here.

     macOS Pods are single-container: the same `runner` container
     runs the poll loop inside the Tart VM and execs `./run.sh`
     in place on a successful claim. `started=true` is true the
     moment the VM boots — long before any dispatch — so it is
     NOT a signal that a customer job began. We discriminate by
     spec (presence of a `poller` init container) and apply this
     check only when it carries useful information.

  The wedge signature this worker was built for (poller polls
  forever without ever receiving a JIT) still trips the reap
  because: claim absent, session absent (open was never called),
  and in the Linux case the runner container never leaves
  `waiting`.

  The check is intentionally conservative: it prefers leaking a
  Pod for one more reconcile cycle (the Pool reconciler will
  eventually reap it once the runner exits) over killing a live
  build.

  ## Finished-job override

  Both shields assume the runner eventually exits and the Pod
  reaches a terminal phase, which is what closes the session and
  hands the Pod to the Pool reconciler. On 2026-09-02 that
  assumption broke: runner processes died mid-job (ENOSPC inside
  the microVM) without the `runner` container ever terminating, so
  `started=true` stayed set, the controller never reported
  `pods/stopped`, the session stayed open, and nine Pods sat
  Running for five hours holding their slots and their
  writable-layer snapshots. Nothing in the system had an exit for
  a Running Pod whose runner was dead.

  The one fact that survives that failure is GitHub's: it marked
  each job `completed` within seconds, and the `workflow_job`
  webhook recorded it. A Pod runs exactly one job, so a session
  whose job has been terminal for longer than `@finished_seconds`
  is not executing anything, whatever its container reports. Such
  a Pod loses the session and container-started shields and is
  reaped. It keeps the claim shield: a live claim on a finished
  job is a database inconsistency for the claim sweeps to resolve,
  and over-reaping is the worse error. The window is wide enough
  that a runner finishing normally is long reaped by the Pool
  reconciler before this ever looks at it.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Environment
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.Claims
  alias Tuist.Runners.RunnerSessions
  alias Tuist.Runners.Telemetry
  alias Tuist.Runners.WorkflowJobs

  require Logger

  @owner_label "tuist.dev/runner-pool-owner"
  @grace_seconds 300
  # How long a session's job must have been terminal on GitHub before
  # the Pod is treated as finished regardless of its container state.
  # A runner that finishes normally exits within seconds and is reaped
  # by the Pool reconciler within a minute; this leaves an order of
  # magnitude for a slow teardown before a Pod is judged dead.
  @finished_seconds 900

  @impl Oban.Worker
  def perform(_job) do
    namespace = Environment.runners_namespace()

    case K8sClient.list_pods(namespace, @owner_label) do
      {:ok, pods} ->
        reap_orphans(namespace, pods)

      {:error, reason} ->
        Logger.warning("runners: orphaned-stamped-pods list failed; will retry next tick",
          reason: inspect(reason)
        )

        :ok
    end
  end

  defp reap_orphans(namespace, pods) do
    now = DateTime.utc_now()
    cutoff = DateTime.add(now, -@grace_seconds, :second)

    # Pods whose session's job GitHub has already closed. These are done
    # whatever their containers say, so they get neither the session nor
    # the container-started shield below.
    finished = finished_pod_names(now, cutoff)

    # Two independent "this Pod is in flight" signals, unioned. Claims
    # cover the normal busy state; sessions cover the gap where the
    # claim was released after dispatch committed but before the Pod
    # actually stopped (the silent-delete class this worker has been
    # observed to produce on a `Claims.release` race). Pods is read
    # *before* both sets — same race-safety argument as `live`.
    live =
      MapSet.union(
        Claims.live_pod_names(),
        MapSet.difference(RunnerSessions.live_pod_names(), finished)
      )

    {finished_reaped, wedged_reaped} =
      pods
      |> Enum.filter(&(orphaned?(&1, live, finished, cutoff) and reap(namespace, &1)))
      |> Enum.split_with(&MapSet.member?(finished, get_in(&1, ["metadata", "name"])))

    record_reaped(length(wedged_reaped), "orphaned_stamped_pod", "runners: reaped orphaned stamped pods")

    record_reaped(
      length(finished_reaped),
      "finished_job_pod",
      "runners: reaped stamped pods whose job GitHub already completed"
    )

    :ok
  end

  defp record_reaped(0, _kind, _message), do: :ok

  defp record_reaped(count, kind, message) do
    Logger.warning(message, count: count, grace_seconds: @grace_seconds)

    :telemetry.execute(
      Telemetry.event_name_recovery(),
      %{count: count},
      %{kind: kind}
    )
  end

  # Open sessions whose job reached a terminal status on GitHub more
  # than @finished_seconds ago. The job that actually ran outranks the
  # one the claim was minted for: GitHub hands a queued job to any
  # eligible runner, so the two can differ, and `executed_workflow_job_id`
  # is nil when GitHub never told us (a job that failed before its
  # in_progress webhook, as on a wedged box).
  defp finished_pod_names(now, session_threshold) do
    sessions = RunnerSessions.list_open_for_pod_reconciliation(session_threshold)

    completions =
      sessions
      |> Enum.flat_map(&[&1.executed_workflow_job_id, &1.workflow_job_id])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> WorkflowJobs.terminal_completions()

    finished_before = DateTime.add(now, -@finished_seconds, :second)

    sessions
    |> Enum.filter(fn session ->
      case Map.get(completions, session.executed_workflow_job_id) || Map.get(completions, session.workflow_job_id) do
        nil -> false
        completed_at -> DateTime.before?(completed_at, finished_before)
      end
    end)
    |> MapSet.new(& &1.pod_name)
  end

  defp orphaned?(pod, live, finished, cutoff) do
    name = get_in(pod, ["metadata", "name"])

    is_binary(name) and
      not MapSet.member?(live, name) and
      created_before?(pod, cutoff) and
      (MapSet.member?(finished, name) or not linux_runner_executing?(pod))
  end

  # True if the Pod is a Linux split-container runner whose `runner`
  # container has begun executing a job — i.e., the `poller` init
  # container successfully staged a JIT and kubelet started the
  # `runner` container, OR the runner has already executed and
  # terminated.
  #
  # ## Why this is Linux-only
  #
  # The Linux Pod shape isolates dispatch from execution across two
  # containers: a `poller` init container holds the SA token and
  # polls for a claim; only after it stages a JIT does kubelet start
  # the credential-free `runner` container that runs `./run.sh`. So
  # the `runner` container reaching `started=true` is unambiguous
  # proof that a JIT was delivered and the Pod is or was running a
  # customer job.
  #
  # The macOS Pod shape is single-container: the same `runner`
  # container runs the poll loop (`dispatch-poll.sh`) inside the
  # Tart VM and, on a successful claim, execs `./run.sh` in place.
  # That means `started=true` is true the moment the VM boots — long
  # before any dispatch has happened — so it is NOT a signal that a
  # customer job has begun. Applying the guard to macOS would turn
  # the worker into a no-op for that shape: a stamped/no-claim macOS
  # Pod (the exact wedge `release_safely/3` can produce) would be
  # protected indefinitely, and the macOS poll loop's
  # retry-on-5xx-forever behaviour would never get cleaned up.
  #
  # We discriminate by spec: only the Linux shape carries a `poller`
  # init container.
  defp linux_runner_executing?(pod) do
    linux_split_container?(pod) and runner_container_started?(pod)
  end

  defp linux_split_container?(pod) do
    pod
    |> get_in(["spec", "initContainers"])
    |> List.wrap()
    |> Enum.any?(&(&1["name"] == "poller"))
  end

  defp runner_container_started?(pod) do
    pod
    |> get_in(["status", "containerStatuses"])
    |> List.wrap()
    |> Enum.find(&(&1["name"] == "runner"))
    |> case do
      nil ->
        false

      status ->
        # `started: true` flips on once the container is up; it can
        # flip back to false on termination, so also accept a present
        # `state.terminated` or `lastState.terminated` as proof the
        # runner already executed.
        Map.get(status, "started") == true or
          not is_nil(get_in(status, ["state", "terminated"])) or
          not is_nil(get_in(status, ["lastState", "terminated"]))
    end
  end

  defp created_before?(pod, cutoff) do
    case pod |> get_in(["metadata", "creationTimestamp"]) |> parse_timestamp() do
      {:ok, created_at} -> DateTime.before?(created_at, cutoff)
      :error -> false
    end
  end

  defp parse_timestamp(ts) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, created_at, _offset} -> {:ok, created_at}
      {:error, _} -> :error
    end
  end

  defp parse_timestamp(_), do: :error

  defp reap(namespace, pod) do
    name = get_in(pod, ["metadata", "name"])

    case K8sClient.delete_runner(namespace, name) do
      :ok ->
        Logger.warning("runners: reaped orphaned stamped pod", pod: name)
        true

      {:error, reason} ->
        Logger.warning("runners: reap of orphaned stamped pod failed; will retry next tick",
          pod: name,
          reason: inspect(reason)
        )

        false
    end
  end
end
