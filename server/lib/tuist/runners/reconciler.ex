defmodule Tuist.Runners.Reconciler do
  @moduledoc """
  Maintains the shared warm pool of generic runner Pods.

  Pure-ish: reads observed cluster state from
  `Tuist.Kubernetes.Client`, computes desired-vs-actual against
  `Tuist.Runners.PoolConfig.total_warm_target/0`, and emits
  Pod-create requests to close the gap.

  Cron-paced (60 s) by `Tuist.Runners.Workers.ReconcilePoolsWorker`.
  Idempotent — safe to invoke twice in the same minute (we'd just
  create twice the gap, which converges next tick), but the cron
  is configured singleton.

  Doesn't delete Pods: warm runners exit on their own after one
  job (`./run.sh --jitconfig --ephemeral`); shrinking the pool is
  a v2 concern when concurrency tiers become customer-tunable.
  """

  alias Tuist.Environment
  alias Tuist.Kubernetes.Client
  alias Tuist.Runners
  alias Tuist.Runners.PodSpec
  alias Tuist.Runners.PoolConfig

  require Logger

  @doc """
  Runs one reconcile pass. Always returns `:ok` — errors are
  logged but not surfaced (the cron retries on the next tick).
  """
  def reconcile do
    target = PoolConfig.total_warm_target()

    if target == 0 do
      :ok
    else
      case Client.list_pods(PodSpec.namespace(), PodSpec.selector_label()) do
        {:ok, pods} ->
          alive = Enum.count(pods, &PodSpec.alive?/1)
          gap = max(0, target - alive)

          Logger.info("runners: reconcile",
            target: target,
            observed: alive,
            gap: gap
          )

          Enum.each(1..gap//1, fn _ -> create_warm_pod() end)
          :ok

        {:error, :not_in_cluster} ->
          Logger.debug("runners: skipping reconcile — not running in-cluster")
          :ok

        {:error, reason} ->
          Logger.warning("runners: reconcile list_pods failed: #{inspect(reason)}")
          :ok
      end
    end
  end

  defp create_warm_pod do
    name = PodSpec.generate_name()
    image = Environment.runner_image()
    dispatch_url = Environment.runner_dispatch_url()
    fleet = Environment.runners_fleet_name()
    token = generate_dispatch_token()

    pod = PodSpec.build(name, image, dispatch_url, token, fleet)

    with {:ok, %{"metadata" => %{"uid" => uid, "name" => pod_name}}} <-
           Client.create_pod(PodSpec.namespace(), pod),
         {:ok, _} <-
           Runners.create_idle_assignment(%{
             pod_uid: uid,
             pod_name: pod_name,
             dispatch_token_hash: Runners.hash_token(token)
           }) do
      Logger.info("runners: created warm pod",
        pod_name: pod_name,
        pod_uid: uid,
        image: image,
        fleet: fleet
      )

      :ok
    else
      {:error, %Ecto.Changeset{} = cs} ->
        # Insertion failure after a successful Pod create leaks a
        # Pod we can't authenticate. Log loudly: a hand-deleted
        # Pod is the cleanest recovery, and the next reconcile
        # tick will create a replacement once it's gone.
        Logger.error("runners: persisted assignment failed; orphaned Pod will need manual cleanup",
          changeset_errors: inspect(cs.errors)
        )

        :ok

      {:error, reason} ->
        Logger.warning("runners: create_pod failed: #{inspect(reason)}")
        :ok
    end
  end

  defp generate_dispatch_token do
    32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end
end
