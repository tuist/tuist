defmodule Pulse.Storage.S3.ObjectCache do
  @moduledoc """
  Disposable node-local read cache of immutable segment objects.

  Segment, rollup and compaction outputs are written once under keys that
  are never reused for different bytes (random suffixes; keyed `-idem-`
  objects are excluded), so a cached body never needs invalidation: queries
  only ask for keys their manifest still references. Dashboards re-read the
  same recent segments every refresh, and maintenance re-reads the segments
  this node has just uploaded, so both are served from here instead of a
  billed GET with object-store latency.

    * Memory tier: byte-bounded LRU of refcounted binaries
      (`PULSE_OBJECT_CACHE_MEMORY_MB`). Cleared under node memory pressure.
    * Disk tier (optional, `PULSE_OBJECT_CACHE_DIR` and
      `PULSE_OBJECT_CACHE_DISK_MB`): byte-bounded LRU of files, rescanned at
      boot so a restarted container keeps its working set. Files are written
      to a temporary name and renamed, so a crash never leaves a partial body.
    * Single flight: concurrent misses for one key share one GET.
    * Write-through (`put/2`) after this node uploads an object: into the
      disk tier when it is configured, otherwise into memory.

  Nothing here is authoritative: a miss, a full cache or a disabled cache only
  costs a GET. Byte budgets for scans are charged by callers on the returned
  body, so cached and uncached reads admit exactly the same queries.
  """
  use Pulse.Runtime.GenServer

  alias Pulse.ObjectStore
  alias Pulse.Runtime.GenServer

  @table __MODULE__
  @memory Module.concat(__MODULE__, Memory)
  @memory_lru Module.concat(__MODULE__, MemoryLRU)
  @disk Module.concat(__MODULE__, Disk)
  @disk_lru Module.concat(__MODULE__, DiskLRU)
  # Entries larger than this share of a tier would evict most of it.
  @max_entry_share 4

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  defp table(name), do: Pulse.Runtime.table(name)

  @doc "Whether `key` names an object this cache may hold."
  def cacheable?(key), do: String.ends_with?(key, ".parquet") and not String.contains?(key, "-idem-")

  @doc "Like `ObjectStore.get/2`, served from the cache when possible."
  def get(config, key), do: fetch(config, key, nil)

  @doc """
  Like `ObjectStore.get_bounded/4` without an ETag, returning `{:ok, body}`:
  `{:error, :response_too_large}` when the object exceeds `limit` bytes.
  """
  def get_bounded(config, key, limit) when is_integer(limit) and limit > 0, do: fetch(config, key, limit)

  @doc "Write-through for an object this node has just uploaded."
  def put(key, body) when is_binary(key) and is_binary(body) do
    if enabled?() and cacheable?(key), do: GenServer.cast(__MODULE__, {:put, key, body, :write})
    :ok
  catch
    :exit, _ -> :ok
  end

  @doc "Drop the memory tier (memory pressure); the disk tier stays."
  def clear_memory do
    if pid = Pulse.Runtime.whereis(__MODULE__), do: send(pid, :clear_memory)
    :ok
  end

  @doc "`%{memory: {entries, bytes}, disk: {entries, bytes}}` and hit counters."
  def stats do
    [{:stats, stats}] = :ets.lookup(table(@table), :stats)
    counters = for name <- [:memory_hits, :disk_hits, :misses, :shared], into: %{}, do: {name, counter(name)}
    Map.merge(stats, counters)
  rescue
    ArgumentError -> %{memory: {0, 0}, disk: {0, 0}, memory_hits: 0, disk_hits: 0, misses: 0, shared: 0}
  end

  defp enabled? do
    match?([{:enabled, true}], :ets.lookup(table(@table), :enabled))
  rescue
    ArgumentError -> false
  end

  # ---- read path (caller process) -------------------------------------------

  defp fetch(config, key, limit) do
    if enabled?() and cacheable?(key) do
      case lookup(key) do
        {:ok, body} -> bounded(body, limit)
        :miss -> fetch_shared(config, key, limit)
      end
    else
      direct(config, key, limit)
    end
  end

  defp bounded(body, limit) when is_integer(limit) and byte_size(body) > limit, do: {:error, :response_too_large}
  defp bounded(body, _limit), do: {:ok, body}

  defp lookup(key) do
    case :ets.lookup(table(@memory), key) do
      [{^key, body, _size, tick}] ->
        touch(@memory, @memory_lru, key, tick)
        bump(:memory_hits)
        {:ok, body}

      [] ->
        lookup_disk(key)
    end
  end

  defp lookup_disk(key) do
    with [{^key, path, _size, tick}] <- :ets.lookup(table(@disk), key),
         {:ok, body} <- File.read(path) do
      touch(@disk, @disk_lru, key, tick)
      bump(:disk_hits)
      GenServer.cast(__MODULE__, {:put, key, body, :read})
      {:ok, body}
    else
      [] ->
        :miss

      {:error, _} ->
        GenServer.cast(__MODULE__, {:forget, key})
        :miss
    end
  end

  # Replace the entry's LRU position. Concurrent touches can leave a stale
  # position behind; eviction skips positions that no longer match.
  defp touch(entries, lru, key, tick) do
    next = System.unique_integer([:monotonic])
    :ets.delete(table(lru), {tick, key})
    :ets.insert(table(lru), {{next, key}})
    :ets.update_element(table(entries), key, {4, next})
  end

  defp fetch_shared(config, key, limit) do
    case GenServer.call(__MODULE__, {:claim, key}, :infinity) do
      :leader ->
        bump(:misses)
        result = direct(config, key, limit)
        if match?({:ok, _}, result), do: GenServer.cast(__MODULE__, {:put, key, elem(result, 1), :read})
        GenServer.cast(__MODULE__, {:complete, key, self(), shared_result(result, limit)})
        result

      {:shared, {:ok, body}} ->
        bump(:shared)
        bounded(body, limit)

      # The leader's tighter bound says nothing about a larger one.
      {:shared, {:too_large, leader_limit}} when limit == nil or limit > leader_limit ->
        direct(config, key, limit)

      {:shared, {:too_large, _}} ->
        {:error, :response_too_large}

      {:shared, {:error, _} = error} ->
        error
    end
  catch
    :exit, _ -> direct(config, key, limit)
  end

  defp shared_result({:error, :response_too_large}, limit), do: {:too_large, limit}
  defp shared_result(result, _limit), do: result

  defp direct(config, key, nil), do: ObjectStore.get(config, key)

  defp direct(config, key, limit) do
    case ObjectStore.get_bounded(config, key, nil, limit) do
      {:ok, _etag, body} -> {:ok, body}
      other -> other
    end
  end

  defp bump(name), do: :ets.update_counter(table(@table), name, 1, {name, 0})

  defp counter(name) do
    case :ets.lookup(table(@table), name) do
      [{^name, count}] -> count
      [] -> 0
    end
  end

  # ---- owner ------------------------------------------------------------------

  @impl true
  def init(opts) do
    config = Keyword.merge(Pulse.Runtime.get_env(:pulse, __MODULE__, []), opts)
    memory_bytes = Keyword.get(config, :memory_bytes, 0)
    dir = Keyword.get(config, :disk_dir)
    disk_bytes = if dir in [nil, ""], do: 0, else: Keyword.get(config, :disk_bytes, 0)

    :ets.new(table(@table), [:named_table, :public, :set, write_concurrency: true])
    for name <- [@memory, @disk], do: :ets.new(table(name), [:named_table, :public, :set, read_concurrency: true])
    for name <- [@memory_lru, @disk_lru], do: :ets.new(table(name), [:named_table, :public, :ordered_set])

    state = %{
      memory: %{max: memory_bytes, bytes: 0},
      disk: %{max: disk_bytes, bytes: 0, dir: dir},
      flights: %{}
    }

    state = if disk_bytes > 0, do: rescan(state), else: state
    :ets.insert(table(@table), {:enabled, memory_bytes > 0 or disk_bytes > 0})
    {:ok, publish(state)}
  end

  @impl true
  def handle_call({:claim, key}, {pid, _} = from, state) do
    case state.flights do
      %{^key => flight} ->
        {:noreply, %{state | flights: Map.put(state.flights, key, %{flight | waiters: [from | flight.waiters]})}}

      _ ->
        ref = Process.monitor(pid)
        {:reply, :leader, %{state | flights: Map.put(state.flights, key, %{leader: pid, ref: ref, waiters: []})}}
    end
  end

  @impl true
  def handle_cast({:complete, key, pid, result}, state) do
    case state.flights do
      %{^key => %{leader: ^pid} = flight} ->
        Process.demonitor(flight.ref, [:flush])
        Enum.each(flight.waiters, &GenServer.reply(&1, {:shared, result}))
        {:noreply, %{state | flights: Map.delete(state.flights, key)}}

      _ ->
        {:noreply, state}
    end
  end

  def handle_cast({:put, key, body, origin}, state) do
    state =
      cond do
        origin == :write and state.disk.max > 0 -> put_disk(state, key, body)
        origin == :read and state.disk.max > 0 and not :ets.member(table(@disk), key) -> put_disk(state, key, body)
        true -> state
      end

    # Written objects go to memory only without a disk tier.
    state = if origin == :read or state.disk.max == 0, do: put_memory(state, key, body), else: state
    {:noreply, publish(state)}
  end

  def handle_cast({:forget, key}, state), do: {:noreply, state |> drop_disk(key) |> publish()}

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Enum.find(state.flights, fn {_key, flight} -> flight.ref == ref end) do
      nil ->
        {:noreply, state}

      # The leader died before completing: the oldest waiter fetches instead.
      {key, %{waiters: []}} ->
        {:noreply, %{state | flights: Map.delete(state.flights, key)}}

      {key, %{waiters: waiters}} ->
        [{pid, _} = next | rest] = Enum.reverse(waiters)
        GenServer.reply(next, :leader)
        flight = %{leader: pid, ref: Process.monitor(pid), waiters: Enum.reverse(rest)}
        {:noreply, %{state | flights: Map.put(state.flights, key, flight)}}
    end
  end

  def handle_info(:clear_memory, state) do
    :ets.delete_all_objects(table(@memory))
    :ets.delete_all_objects(table(@memory_lru))
    {:noreply, publish(%{state | memory: %{state.memory | bytes: 0}})}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp put_memory(%{memory: %{max: max}} = state, key, body) do
    size = byte_size(body)

    if max == 0 or size * @max_entry_share > max or :ets.member(table(@memory), key) or Pulse.MemoryPressure.active?() do
      state
    else
      # Accounted bytes must be the bytes kept alive: never pin a larger parent.
      body = if :binary.referenced_byte_size(body) > size, do: :binary.copy(body), else: body
      tick = System.unique_integer([:monotonic])
      :ets.insert(table(@memory), {key, body, size, tick})
      :ets.insert(table(@memory_lru), {{tick, key}})
      evict(%{state | memory: %{state.memory | bytes: state.memory.bytes + size}}, :memory)
    end
  end

  defp put_disk(%{disk: disk} = state, key, body) do
    size = byte_size(body)

    if size * @max_entry_share > disk.max or :ets.member(table(@disk), key) do
      state
    else
      path = Path.join(disk.dir, Base.url_encode64(key, padding: false))
      tmp = path <> ".tmp"

      with :ok <- File.write(tmp, body), :ok <- File.rename(tmp, path) do
        tick = System.unique_integer([:monotonic])
        :ets.insert(table(@disk), {key, path, size, tick})
        :ets.insert(table(@disk_lru), {{tick, key}})
        evict(%{state | disk: %{disk | bytes: disk.bytes + size}}, :disk)
      else
        _ ->
          File.rm(tmp)
          state
      end
    end
  end

  defp drop_disk(state, key) do
    case :ets.take(table(@disk), key) do
      [{^key, path, size, tick}] ->
        :ets.delete(table(@disk_lru), {tick, key})
        File.rm(path)
        %{state | disk: %{state.disk | bytes: state.disk.bytes - size}}

      [] ->
        state
    end
  end

  defp evict(state, tier) do
    %{bytes: bytes, max: max} = Map.fetch!(state, tier)
    {entries, lru} = if tier == :memory, do: {@memory, @memory_lru}, else: {@disk, @disk_lru}

    with true <- bytes > max, {tick, key} <- :ets.first(table(lru)) do
      :ets.delete(table(lru), {tick, key})

      case :ets.lookup(table(entries), key) do
        [{^key, _body_or_path, _size, ^tick}] when tier == :memory ->
          [{_, _, size, _}] = :ets.take(table(entries), key)
          evict(%{state | memory: %{state.memory | bytes: state.memory.bytes - size}}, tier)

        [{^key, _path, _size, ^tick}] ->
          evict(drop_disk_entry(state, key), tier)

        # A position a concurrent touch replaced.
        _ ->
          evict(state, tier)
      end
    else
      _ -> state
    end
  end

  defp drop_disk_entry(state, key) do
    [{^key, path, size, _}] = :ets.take(table(@disk), key)
    File.rm(path)
    %{state | disk: %{state.disk | bytes: state.disk.bytes - size}}
  end

  # Adopt complete files a previous run left; drop partial writes and files
  # that no longer fit.
  defp rescan(%{disk: %{dir: dir}} = state) do
    File.mkdir_p!(dir)

    dir
    |> File.ls!()
    |> Enum.flat_map(fn name ->
      path = Path.join(dir, name)

      with false <- String.ends_with?(name, ".tmp"),
           {:ok, key} <- Base.url_decode64(name, padding: false),
           true <- cacheable?(key),
           {:ok, %File.Stat{type: :regular, size: size, mtime: mtime}} <- File.stat(path, time: :posix) do
        [{mtime, key, path, size}]
      else
        _ ->
          File.rm_rf(path)
          []
      end
    end)
    |> Enum.sort()
    |> Enum.reduce(state, fn {_mtime, key, path, size}, state ->
      tick = System.unique_integer([:monotonic])
      :ets.insert(table(@disk), {key, path, size, tick})
      :ets.insert(table(@disk_lru), {{tick, key}})
      evict(%{state | disk: %{state.disk | bytes: state.disk.bytes + size}}, :disk)
    end)
  end

  defp publish(state) do
    stats = %{
      memory: {:ets.info(table(@memory), :size), state.memory.bytes},
      disk: {:ets.info(table(@disk), :size), state.disk.bytes}
    }

    :ets.insert(table(@table), {:stats, stats})
    state
  end
end
