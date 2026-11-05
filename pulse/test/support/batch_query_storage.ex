defmodule Pulse.Test.BatchQueryStorage do
  @moduledoc false
  @behaviour Pulse.Storage

  def append(_, _, _, _), do: {:error, :unexpected_append}

  def query(signal, tenant, opts) when signal in [:metrics, :logs] do
    owner = Pulse.Runtime.fetch_env!(:pulse, __MODULE__)
    ref = Process.monitor(owner)
    send(owner, {:batch_query, self(), tenant, opts})

    receive do
      {:release_batch, result} ->
        Process.demonitor(ref, [:flush])
        result

      {:DOWN, ^ref, :process, ^owner, _} ->
        {:error, :query_timeout}
    end
  end
end
