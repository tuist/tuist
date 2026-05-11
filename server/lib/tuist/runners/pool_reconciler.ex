defmodule Tuist.Runners.PoolReconciler do
  @moduledoc """
  Reconciles `runner_pools` DB rows into `RunnerPool` CRs in the
  cluster's runners namespace. The DB is the system of record; the
  CR is derived state the runners-controller (Go) consumes.

  Architecture:

      Tuist.Runners.PoolReconciler (this GenServer)
        ├─ on init: subscribe to PubSub, run full sync
        ├─ on `{:pool_*, _}` PubSub event: kick a throttled sync
        ├─ on periodic `:tick` (60 s): safety-net full sync
        └─ on each sync:
              1. Take a Postgres advisory lock (one replica drives)
              2. LIST DB rows + LIST K8s CRs labeled
                 `tuist.dev/managed-by=tuist-server`
              3. Diff and apply CREATE/UPDATE/DELETE to K8s

  Only CRs labeled `tuist.dev/managed-by=tuist-server` are touched
  — operator-applied or chart-rendered CRs without that label are
  left alone, so a self-hoster can mix DB-driven pools with manual
  ones if they want.

  Returns `:ignore` when running outside a cluster (no apiserver
  reachable) so local dev / preview / self-host deployments without
  the runners feature don't churn on transient errors.
  """

  use GenServer

  alias Tuist.Environment
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Repo
  alias Tuist.Runners.Pool
  alias Tuist.Runners.Pools

  require Logger

  # 63-bit constant, stable across the codebase. The reconciler is
  # cluster-wide single-owner via this lock so multiple BEAM nodes
  # don't race on K8s create/update.
  @advisory_lock_id 4_223_915_876_100

  # Coalesces a burst of PubSub events into one sync run.
  @debounce_ms 500

  # Catch-all sync — covers missed PubSub events (process restart,
  # message-loss edge cases) and drift between DB and K8s (manual
  # `kubectl edit` on a managed CR, etc.).
  @tick_ms 60_000

  @managed_by_label "tuist.dev/managed-by"
  @managed_by_value "tuist-server"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Force a sync from outside (ops command, test). Throttled the same
  way PubSub events are.
  """
  def kick do
    if Process.whereis(__MODULE__) do
      GenServer.cast(__MODULE__, :reconcile)
      :ok
    else
      {:error, :not_running}
    end
  end

  @impl GenServer
  def init(_opts) do
    Pools.subscribe()
    Process.send_after(self(), :tick, @tick_ms)
    send(self(), :reconcile_now)
    {:ok, %{pending: false}}
  end

  @impl GenServer
  def handle_info(:reconcile_now, state) do
    do_reconcile()
    {:noreply, %{state | pending: false}}
  end

  def handle_info({:pool_created, _}, state), do: {:noreply, schedule(state)}
  def handle_info({:pool_updated, _}, state), do: {:noreply, schedule(state)}
  def handle_info({:pool_deleted, _}, state), do: {:noreply, schedule(state)}

  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, @tick_ms)
    do_reconcile()
    {:noreply, %{state | pending: false}}
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def handle_cast(:reconcile, state) do
    do_reconcile()
    {:noreply, %{state | pending: false}}
  end

  defp schedule(%{pending: true} = state), do: state

  defp schedule(state) do
    Process.send_after(self(), :reconcile_now, @debounce_ms)
    %{state | pending: true}
  end

  defp do_reconcile do
    _ =
      Repo.transaction(fn ->
        case Repo.query!("SELECT pg_try_advisory_xact_lock($1)", [@advisory_lock_id]) do
          %{rows: [[true]]} ->
            sync_to_cluster()
            :ok

          _ ->
            Logger.debug("runners: pool reconcile skipped — lock held elsewhere")
            :skipped
        end
      end)

    :ok
  rescue
    e ->
      Logger.error("runners: pool reconcile crashed", error: Exception.message(e))
      :ok
  end

  defp sync_to_cluster do
    namespace = Environment.runners_namespace()
    db_rows = Pools.list_pools()

    case K8sClient.list_runner_pools(namespace) do
      {:ok, cluster_items} ->
        managed_items = Enum.filter(cluster_items, &managed?/1)
        apply_diff(namespace, db_rows, managed_items)

      {:error, :not_in_cluster} ->
        # Out-of-cluster (local dev). Don't churn on the next tick;
        # the operator picks up the actual state when redeployed.
        :ok

      {:error, reason} ->
        Logger.warning("runners: pool reconcile list failed", reason: inspect(reason))
        :ok
    end
  end

  defp managed?(%{"metadata" => %{"labels" => labels}}) when is_map(labels) do
    Map.get(labels, @managed_by_label) == @managed_by_value
  end

  defp managed?(_), do: false

  defp apply_diff(namespace, db_rows, cluster_items) do
    cluster_by_name = Map.new(cluster_items, fn cr -> {cr["metadata"]["name"], cr} end)
    db_by_name = Map.new(db_rows, fn row -> {row.name, row} end)

    # Creates + updates.
    Enum.each(db_rows, fn row ->
      case Map.get(cluster_by_name, row.name) do
        nil -> create(namespace, row)
        cr -> maybe_update(namespace, row, cr)
      end
    end)

    # Deletes — managed CRs whose DB row is gone.
    cluster_items
    |> Enum.reject(fn cr -> Map.has_key?(db_by_name, cr["metadata"]["name"]) end)
    |> Enum.each(fn cr -> delete(namespace, cr["metadata"]["name"]) end)
  end

  defp create(namespace, %Pool{} = row) do
    manifest = manifest_for(namespace, row)

    case K8sClient.create_runner_pool(namespace, manifest) do
      {:ok, _} ->
        Logger.info("runners: pool reconcile created CR", pool: row.name)
        :ok

      {:error, :conflict} ->
        # CR exists but doesn't carry our managed-by label. Surface
        # loudly — we don't take over a CR we didn't create.
        Logger.warning("runners: pool reconcile skipped create — CR exists without managed-by",
          pool: row.name
        )

        :ok

      {:error, reason} ->
        Logger.warning("runners: pool reconcile create failed",
          pool: row.name,
          reason: inspect(reason)
        )

        :ok
    end
  end

  defp maybe_update(namespace, %Pool{} = row, cr) do
    desired_spec = spec_for(row)
    current_spec = Map.get(cr, "spec", %{})

    if desired_spec == current_spec do
      :ok
    else
      updated =
        cr
        |> Map.put("spec", desired_spec)
        |> put_in(["metadata", "labels"], merge_labels(cr["metadata"]["labels"], row))

      case K8sClient.update_runner_pool(namespace, row.name, updated) do
        {:ok, _} ->
          Logger.info("runners: pool reconcile updated CR", pool: row.name)
          :ok

        {:error, :conflict} ->
          # Another writer beat us; next tick will reconcile.
          :ok

        {:error, reason} ->
          Logger.warning("runners: pool reconcile update failed",
            pool: row.name,
            reason: inspect(reason)
          )

          :ok
      end
    end
  end

  defp delete(namespace, name) do
    case K8sClient.delete_runner_pool(namespace, name) do
      {:ok, _} ->
        Logger.info("runners: pool reconcile deleted CR", pool: name)
        :ok

      {:error, reason} ->
        Logger.warning("runners: pool reconcile delete failed",
          pool: name,
          reason: inspect(reason)
        )

        :ok
    end
  end

  defp manifest_for(namespace, %Pool{} = row) do
    %{
      "apiVersion" => "tuist.dev/v1alpha1",
      "kind" => "RunnerPool",
      "metadata" => %{
        "name" => row.name,
        "namespace" => namespace,
        "labels" => labels_for(row)
      },
      "spec" => spec_for(row)
    }
  end

  defp labels_for(%Pool{role: role} = row) do
    base = %{
      "app.kubernetes.io/component" => "runners-controller",
      "app.kubernetes.io/managed-by" => "tuist-server",
      @managed_by_label => @managed_by_value,
      "tuist.dev/runner-pool-role" => role_to_crd(role)
    }

    if role == "customer" and row.owner != "" do
      Map.put(base, "tuist.dev/runner-pool-owner", row.owner)
    else
      base
    end
  end

  defp merge_labels(nil, row), do: labels_for(row)

  defp merge_labels(existing, row) when is_map(existing) do
    Map.merge(existing, labels_for(row))
  end

  defp spec_for(%Pool{} = row) do
    base = %{
      "role" => role_to_crd(row.role),
      "labels" => row.labels || [],
      "minWarm" => row.min_warm || 0,
      "image" => row.image || Environment.runner_image_default(),
      "fleetSelector" => row.fleet_selector || Environment.runners_default_fleet(),
      "podCPUMilli" => row.pod_cpu_milli || Environment.runner_pod_cpu_milli_default(),
      "podMemoryMB" => row.pod_memory_mb || Environment.runner_pod_memory_mb_default()
    }

    base
    |> maybe_put("owner", row.owner)
    |> maybe_put("runnerGroupID", row.runner_group_id)
    |> maybe_put("allowedRepos", row.allowed_repos)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp role_to_crd("shared_warm"), do: "SharedWarm"
  defp role_to_crd(_), do: "Customer"
end
