defmodule Tuist.Runners.Reconciler do
  @moduledoc """
  Pure reconciliation logic for Orchard worker pools.

  Given a pool id, looks at the pool's spec (`desired_size`, Scaleway config)
  and its observed workers, then drives the fleet toward the spec by creating
  new worker rows (and enqueueing `ProvisionOrchardWorkerWorker` jobs) or
  marking existing workers for deprovisioning.

  This function is idempotent: calling it repeatedly with no drift is a no-op.
  It has no side effects beyond database writes and `Oban.insert`, so it's
  safe to call from either an Oban cron, a button click, or a Bonny
  controller's reconcile step.
  """

  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Runners
  alias Tuist.Runners.OrchardWorker
  alias Tuist.Runners.OrchardWorkerPool
  alias Tuist.Runners.Workers.DeprovisionOrchardWorkerWorker
  alias Tuist.Runners.Workers.ProvisionOrchardWorkerWorker

  require Logger

  def reconcile_all do
    Enum.map(Runners.list_enabled_orchard_worker_pools(), fn pool ->
      {pool.id, reconcile(pool.id)}
    end)
  end

  def reconcile(pool_id) do
    with {:ok, pool} <- Runners.get_orchard_worker_pool(pool_id) do
      do_reconcile(pool)
    end
  end

  defp do_reconcile(%OrchardWorkerPool{enabled: false} = pool) do
    drained = drain_all_active(pool)

    {:ok, _} =
      Runners.update_orchard_worker_pool_status(pool, %{
        last_reconciled_at: now()
      })

    {:ok, %{action: :disabled, drained: drained}}
  end

  defp do_reconcile(%OrchardWorkerPool{} = pool) do
    active = Runners.list_active_workers_in_pool(pool.id)
    current_size = length(active)
    desired = pool.desired_size

    result =
      cond do
        current_size < desired -> scale_up(pool, desired - current_size)
        current_size > desired -> scale_down(active, current_size - desired)
        true -> %{action: :steady, size: current_size}
      end

    {:ok, _} =
      Runners.update_orchard_worker_pool_status(pool, %{
        last_reconciled_at: now()
      })

    {:ok, Map.put(result, :desired_size, desired)}
  end

  defp scale_up(%OrchardWorkerPool{} = pool, n) do
    Logger.info("Reconciler scaling up pool #{pool.id} by #{n}")

    created =
      Enum.map(1..n, fn _ ->
        name = new_worker_name(pool)

        {:ok, worker} =
          Runners.create_orchard_worker(%{
            pool_id: pool.id,
            name: name,
            scaleway_zone: pool.scaleway_zone,
            scaleway_server_type: pool.scaleway_server_type,
            scaleway_os: pool.scaleway_os
          })

        {:ok, _job} =
          %{"orchard_worker_id" => worker.id}
          |> ProvisionOrchardWorkerWorker.new()
          |> Oban.insert()

        worker.id
      end)

    %{action: :scaled_up, created: created}
  end

  defp scale_down(active, n) do
    victims =
      active
      |> Enum.sort_by(&scale_down_priority/1)
      |> Enum.take(n)

    Logger.info("Reconciler scaling down by #{n} (picked #{length(victims)})")

    drained =
      Enum.map(victims, fn worker ->
        {:ok, _} = Runners.update_orchard_worker(worker, %{status: :draining})

        {:ok, _job} =
          %{"orchard_worker_id" => worker.id}
          |> DeprovisionOrchardWorkerWorker.new()
          |> Oban.insert()

        worker.id
      end)

    %{action: :scaled_down, drained: drained}
  end

  defp drain_all_active(pool) do
    pool.id
    |> Runners.list_active_workers_in_pool()
    |> Enum.map(fn worker ->
      {:ok, _} = Runners.update_orchard_worker(worker, %{status: :draining})

      {:ok, _job} =
        %{"orchard_worker_id" => worker.id}
        |> DeprovisionOrchardWorkerWorker.new()
        |> Oban.insert()

      worker.id
    end)
  end

  # Prefer draining workers that haven't started real work yet, then oldest.
  defp scale_down_priority(%OrchardWorker{status: :queued, inserted_at: ts}), do: {0, ts}
  defp scale_down_priority(%OrchardWorker{status: :provisioning, inserted_at: ts}), do: {1, ts}
  defp scale_down_priority(%OrchardWorker{status: :online, inserted_at: ts}), do: {2, ts}
  defp scale_down_priority(%OrchardWorker{inserted_at: ts}), do: {3, ts}

  defp new_worker_name(%OrchardWorkerPool{} = pool) do
    suffix = 6 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
    "#{pool.name}-#{suffix}"
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)

  @doc """
  Ecto query returning pool ids that have at least one worker in the given
  status set. Useful for targeted reconciler wake-ups.
  """
  def pool_ids_with_worker_status(statuses) do
    Repo.all(from(w in OrchardWorker, where: w.status in ^statuses, select: w.pool_id, distinct: true))
  end
end
