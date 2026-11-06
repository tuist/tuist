defmodule Pulse.Storage.S3.MetadataCache do
  @moduledoc "Disposable, bounded node-local cache of validated immutable manifest pages."
  use Pulse.Runtime.GenServer

  alias Pulse.Runtime.GenServer

  @table __MODULE__
  @bytes 16_777_216
  @entries 512

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  # Every table operation goes through the current runtime's instance name.
  defp table, do: Pulse.Runtime.table(@table)
  @impl true
  def init(_opts) do
    :ets.new(table(), [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{bytes: 0}}
  end

  def get(ref) do
    case :ets.lookup(table(), ref["k"]) do
      [{_, ^ref, data, _, _}] ->
        :ets.update_element(table(), ref["k"], {5, System.monotonic_time(:millisecond)})
        {:ok, data}

      _ ->
        :miss
    end
  rescue
    ArgumentError -> :miss
  end

  def put(ref, data) do
    # References decoded from a root can contain sub-binaries that pin the
    # entire root generation. Retain only independent reference strings.
    ref = copy_reference(ref)
    # Newly written leaf data may still refer to a much larger decoded root.
    # Accounted leaf bytes cannot cover that arena: detach its strings too.
    data = copy_reference(data)
    GenServer.call(__MODULE__, {:put, ref, data})
  catch
    :exit, _ -> :ok
  end

  @doc false
  def clear, do: GenServer.call(__MODULE__, :clear)

  @doc "Cached pages and their accounted bytes (the quantity bounded by the cache ceiling)."
  def stats do
    GenServer.call(__MODULE__, :stats, 1000)
  catch
    :exit, _ -> {0, 0}
  end

  @impl true
  def handle_call(:clear, _from, _state) do
    :ets.delete_all_objects(table())
    {:reply, :ok, %{bytes: 0}}
  end

  def handle_call(:stats, _from, state) do
    memory = :ets.info(table(), :memory) * :erlang.system_info(:wordsize) + state.bytes
    {:reply, {:ets.info(table(), :size), memory}, state}
  end

  def handle_call({:put, ref, data}, _from, state) do
    old =
      case :ets.lookup(table(), ref["k"]) do
        [{_, _, _, bytes, _}] -> bytes
        [] -> 0
      end

    reference_bytes = IO.iodata_length(Pulse.JSON.encode_to_iodata!(ref))

    bytes = ref["b"] + 2 * reference_bytes
    :ets.insert(table(), {ref["k"], ref, data, bytes, System.monotonic_time(:millisecond)})
    state = evict(%{state | bytes: state.bytes - old + bytes})
    {:reply, :ok, state}
  end

  # Leaf summaries contain nested binaries; shallow copying/accounting could
  # pin an entire decoded index page and evade the cache's byte ceiling.
  defp copy_reference(value) when is_binary(value), do: :binary.copy(value)
  defp copy_reference(value) when is_list(value), do: Enum.map(value, &copy_reference/1)

  defp copy_reference(value) when is_map(value),
    do: Map.new(value, fn {key, val} -> {copy_reference(key), copy_reference(val)} end)

  defp copy_reference(value), do: value

  defp evict(state) do
    # ETS accounts decoded maps, lists, inline binaries and table overhead.
    # Encoded bytes additionally cover reference-counted backing binaries,
    # which are not included in ETS heap-word accounting.
    memory = :ets.info(table(), :memory) * :erlang.system_info(:wordsize) + state.bytes

    if memory > @bytes or :ets.info(table(), :size) > @entries do
      {key, _, _, bytes, _} = :ets.foldl(&least_recent/2, nil, table())
      :ets.delete(table(), key)
      evict(%{state | bytes: state.bytes - bytes})
    else
      state
    end
  end

  defp least_recent(entry, nil), do: entry
  defp least_recent(entry, oldest), do: if(elem(entry, 4) < elem(oldest, 4), do: entry, else: oldest)
end
