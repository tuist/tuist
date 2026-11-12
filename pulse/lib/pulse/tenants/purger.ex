defmodule Pulse.Tenants.Purger do
  @moduledoc """
  Deletes the data of tenants in the `deleting` state, on maintenance
  instances.

  Every `:purge_interval_ms` the purger lists deletion markers. For each tenant
  whose deletion was requested at least `:deletion_grace_ms` ago, it deletes
  objects under `tenants/<tenant>/`, at most `:purge_batch` per tick, so one
  large tenant cannot monopolize the instance or the provider. Once a listing
  finds nothing left, the tenant becomes `deleted` and its marker is removed.

  Several maintenance instances may purge the same tenant at once; deletes are
  idempotent, so overlap costs only duplicate requests. Usage objects live
  outside `tenants/` and are kept.
  """
  use Pulse.Runtime.GenServer

  alias Pulse.ObjectStore
  alias Pulse.Runtime.GenServer
  alias Pulse.Storage.S3.ManifestCache
  alias Pulse.Tenants

  require Logger

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Children for the maintenance role; none unless the registry is enabled."
  def children, do: if(Tenants.enabled?(), do: [__MODULE__], else: [])

  @impl true
  def init(_opts), do: {:ok, schedule()}

  defp schedule, do: Process.send_after(self(), :purge, Tenants.config(:purge_interval_ms, 60_000))

  @doc false
  # Run one purge pass now; for tests and operators.
  def purge, do: GenServer.call(__MODULE__, :purge, 300_000)

  @impl true
  def handle_call(:purge, _from, timer), do: {:reply, run(), timer}

  @impl true
  def handle_info(:purge, _timer) do
    run()
    {:noreply, schedule()}
  end

  def handle_info(_message, timer), do: {:noreply, timer}

  @doc false
  def run do
    with {:ok, storage} <- Tenants.storage(),
         {:ok, keys, _cursor} <- ObjectStore.list_page(storage, Tenants.deletion_prefix(), nil, 100) do
      budget = Tenants.config(:purge_batch, 5_000)

      Enum.reduce_while(keys, %{}, fn key, results ->
        tenant = String.replace_prefix(key, Tenants.deletion_prefix(), "")
        result = purge(storage, tenant, budget)
        {if(result == {:ok, :budget}, do: :halt, else: :cont), Map.put(results, tenant, result)}
      end)
      |> then(&{:ok, &1})
    else
      {:error, reason} = error ->
        Logger.warning("tenant purge pass failed: #{inspect(reason)}")
        error
    end
  end

  defp purge(storage, tenant, budget) do
    case Tenants.read(tenant) do
      {:ok, %{"state" => "deleting", "deletion_requested_at" => at}, _etag} ->
        if System.os_time(:millisecond) - at >= Tenants.config(:deletion_grace_ms, 600_000),
          do: delete_data(storage, tenant, budget),
          else: {:ok, :waiting}

      # The record moved on (or was never written): the marker is stale.
      {:ok, _record, _etag} ->
        with :ok <- ObjectStore.delete(storage, Tenants.deletion_key(tenant)), do: {:ok, :stale}

      {:error, _} = error ->
        error
    end
  end

  defp delete_data(storage, tenant, budget) do
    prefix = "tenants/#{tenant}/"

    case ObjectStore.list_page(storage, prefix, nil, min(budget, 1000)) do
      {:ok, [], _cursor} ->
        for signal <- ~w(logs metrics traces), do: ManifestCache.drop(tenant, signal)

        with :ok <- Tenants.finish_deletion(tenant) do
          Logger.info("tenant #{tenant} purged")
          {:ok, :deleted}
        end

      {:ok, keys, _cursor} ->
        deleted =
          keys
          |> Task.async_stream(&ObjectStore.delete(storage, &1), max_concurrency: 8, timeout: :infinity)
          |> Enum.count(&(&1 == {:ok, :ok}))

        Pulse.SelfMetrics.tenant_purged_objects(deleted)

        cond do
          deleted < length(keys) -> {:error, :tenant_purge_incomplete}
          budget - deleted > 0 -> delete_data(storage, tenant, budget - deleted)
          true -> {:ok, :budget}
        end

      {:error, _} = error ->
        error
    end
  end
end
