defmodule Tuist.Runners.Pools do
  @moduledoc """
  Context for the `runner_pools` table — the system of record for
  per-customer reserved-capacity config. The reconciler
  (`Tuist.Runners.PoolReconciler`) derives a matching `RunnerPool`
  CR in the cluster's runners namespace from each row.

  Public surface intentionally narrow:

    * `list_pools/0`, `get_pool!/1`, `get_pool_by_name/1`,
      `find_shared_warm/0` for the read path (dispatch / reconcile).
    * `create_pool/1`, `update_pool/2`, `delete_pool/1` for the
      write path. Each write broadcasts on `runners:pools` so the
      reconciler picks up the change without waiting for its
      catch-all tick.
  """

  import Ecto.Query

  alias Phoenix.PubSub
  alias Tuist.Repo
  alias Tuist.Runners.Pool

  @pubsub_topic "runners:pools"

  def list_pools do
    Repo.all(from p in Pool, order_by: [asc: p.role, asc: p.name])
  end

  def get_pool!(id), do: Repo.get!(Pool, id)

  def get_pool_by_name(name) when is_binary(name) do
    Repo.get_by(Pool, name: name)
  end

  def find_shared_warm do
    Repo.one(from p in Pool, where: p.role == "shared_warm", limit: 1)
  end

  def create_pool(attrs) do
    %Pool{}
    |> Pool.changeset(attrs)
    |> Repo.insert()
    |> broadcast(:pool_created)
  end

  def update_pool(%Pool{} = pool, attrs) do
    pool
    |> Pool.changeset(attrs)
    |> Repo.update()
    |> broadcast(:pool_updated)
  end

  def delete_pool(%Pool{} = pool) do
    case Repo.delete(pool) do
      {:ok, deleted} = ok ->
        broadcast_ok(deleted, :pool_deleted)
        ok

      err ->
        err
    end
  end

  @doc """
  Returns the topic the reconciler subscribes to for fast-path
  reconciles. `subscribe/0` is the canonical entry point on the
  consumer side.
  """
  def pubsub_topic, do: @pubsub_topic

  @doc """
  Subscribes the calling process to pool mutation events. Used by
  `PoolReconciler` so DB writes produce sub-second K8s reflection.
  """
  def subscribe do
    PubSub.subscribe(Tuist.PubSub, @pubsub_topic)
  end

  defp broadcast({:ok, pool} = ok, event) do
    broadcast_ok(pool, event)
    ok
  end

  defp broadcast(err, _event), do: err

  defp broadcast_ok(pool, event) do
    PubSub.broadcast(Tuist.PubSub, @pubsub_topic, {event, pool})
  end
end
