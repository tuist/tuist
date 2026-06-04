defmodule Tuist.Runners.Workers.OrphanedStampedPodsWorker do
  @moduledoc """
  Reaps runner Pods that carry an owner stamp
  (`tuist.dev/runner-pool-owner`) but have no live Postgres
  `runner_claims` row — "stamped in Kubernetes, unclaimed in the
  database."

  ## Why this exists

  The dispatch path stamps the owner label on a polling Pod the
  instant it wins a claim (`Tuist.Runners.stamp_owner_labels/3`),
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

  Because `Claims.attempt/4` INSERTs the claim *before*
  `stamp_owner_labels/3` runs, an owner-stamped Pod should *always*
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
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Environment
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Telemetry

  require Logger

  @owner_label "tuist.dev/runner-pool-owner"
  @grace_seconds 300

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
    live = Claims.live_pod_names()
    cutoff = DateTime.add(DateTime.utc_now(), -@grace_seconds, :second)

    reaped =
      pods
      |> Enum.filter(&orphaned?(&1, live, cutoff))
      |> Enum.count(&reap(namespace, &1))

    if reaped > 0 do
      Logger.warning("runners: reaped orphaned stamped pods",
        count: reaped,
        grace_seconds: @grace_seconds
      )

      :telemetry.execute(
        Telemetry.event_name_recovery(),
        %{count: reaped},
        %{kind: "orphaned_stamped_pod"}
      )
    end

    :ok
  end

  defp orphaned?(pod, live, cutoff) do
    name = get_in(pod, ["metadata", "name"])

    is_binary(name) and
      not MapSet.member?(live, name) and
      created_before?(pod, cutoff)
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
