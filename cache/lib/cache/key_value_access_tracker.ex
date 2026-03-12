defmodule Cache.KeyValueAccessTracker do
  @moduledoc false

  use GenServer

  alias Cache.Config

  @table __MODULE__

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def mark_shared_lineage(key) when is_binary(key) do
    :ets.insert(@table, {{:lineage, key}, true})
    :ok
  end

  def clear(key) when is_binary(key) do
    :ets.delete(@table, {:lineage, key})
    :ets.delete(@table, {:throttle, key})
    :ok
  end

  def shared_lineage?(key) when is_binary(key) do
    :ets.lookup(@table, {:lineage, key}) != []
  end

  def allow_access_bump?(key) when is_binary(key) do
    now_ms = System.monotonic_time(:millisecond)
    throttle_ms = Config.distributed_kv_access_throttle_ms()

    case :ets.lookup(@table, {:throttle, key}) do
      [{{:throttle, ^key}, last_ms}] when now_ms - last_ms < throttle_ms ->
        false

      _ ->
        :ets.insert(@table, {{:throttle, key}, now_ms})
        true
    end
  end

  @impl true
  def init(state) do
    _table = :ets.new(@table, [:named_table, :public, :set, read_concurrency: true, write_concurrency: true])
    {:ok, state}
  end
end
