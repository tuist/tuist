defmodule Pulse.Test.FailingStorage do
  @moduledoc false
  @behaviour Pulse.Storage

  @impl true
  def append(_signal, _tenant, _records, _opts) do
    case Pulse.Runtime.get_env(:pulse, __MODULE__, :error) do
      :error ->
        {:error, :storage_unavailable}

      :raise ->
        raise "storage crashed"

      {:block, owner} ->
        send(owner, {:append_started, self()})

        receive do
          :continue -> :ok
        end

      {:error, _} = error ->
        error
    end
  end

  @impl true
  def query(_signal, _tenant, _opts), do: {:error, :storage_unavailable}
end
