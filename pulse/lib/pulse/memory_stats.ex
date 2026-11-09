defmodule Pulse.MemoryStats do
  @moduledoc """
  Where this node's memory goes, read without storage I/O or messages to other
  processes, for `pulse_memory_bytes{kind}`, `pulse_memory_ets_bytes{table}`
  and `pulse_memory_process_bytes{group}` on `/metrics`.

  The BEAM only reports what its own allocators hand out
  (`:erlang.memory/0`). A node's resident memory also holds allocator carriers
  that are reserved but unused, native heap allocations of the Rust NIFs, free
  memory the C allocator keeps instead of returning it to the operating system,
  thread stacks and mapped code. Every kind below is measured directly, so
  `rss` minus the measured parts is what remains unattributed.
  """

  alias Pulse.Codec.NIF, as: Codec
  alias Pulse.ObjectStore.NIF

  @allocators [
    :eheap_alloc,
    :binary_alloc,
    :ets_alloc,
    :ll_alloc,
    :fix_alloc,
    :std_alloc,
    :sl_alloc,
    :temp_alloc,
    :driver_alloc,
    :literal_alloc
  ]
  @natives [codec: Codec, object_store: NIF, grpc: Pulse.OTLP.GRPC.NIF]

  @doc "Prometheus text for the memory families; scraping costs one pass over processes and ETS tables."
  @spec render() :: iodata()
  def render do
    [
      family("pulse_memory_bytes", "Node memory by kind; see docs/scaling.md#memory-breakdown.", "kind", kinds()),
      family(
        "pulse_memory_ets_bytes",
        "ETS table memory by table name, excluding referenced binaries.",
        "table",
        ets()
      ),
      family(
        "pulse_memory_process_bytes",
        "Process memory (heap, stack, mailbox) by process group, excluding referenced binaries.",
        "group",
        processes()
      )
    ]
  end

  defp family(name, help, label, values) do
    [
      ["# HELP ", name, " ", help, "\n# TYPE ", name, " gauge\n"]
      | for({key, bytes} <- values, do: [name, "{", label, "=\"", key, "\"} ", Integer.to_string(bytes), "\n"])
    ]
  end

  @doc """
  `{kind, bytes}` pairs. BEAM kinds partition `:erlang.memory(:total)`:
  `processes`, `binary`, `ets`, `code`, `atom` and `system_other`.
  `beam_allocated` is what the BEAM's allocators hold in carriers and
  `beam_allocator_free` the part of it holding no live block (fragmentation).
  `beam_mapped` is all memory the BEAM has mapped for its allocators,
  including freed segments it caches without reporting them (`+MMmcs`).
  `native_<library>` is the live Rust heap of each NIF library. With glibc,
  `malloc_in_use` is everything allocated through the C allocator (the Rust
  heaps, some BEAM carriers, OpenSSL) and `malloc_free` what it keeps free
  without returning it to the operating system. `rss` and `rss_anon` are the
  operating system's resident view (Linux only).
  """
  @spec kinds() :: [{String.t(), non_neg_integer()}]
  def kinds do
    memory = :erlang.memory()
    {used, allocated} = allocators()
    system = memory[:system] - memory[:binary] - memory[:ets] - memory[:code] - memory[:atom]

    [
      {"total", memory[:total]},
      {"processes", memory[:processes]},
      {"binary", memory[:binary]},
      {"ets", memory[:ets]},
      {"code", memory[:code]},
      {"atom", memory[:atom]},
      {"system_other", max(system, 0)},
      {"beam_allocated", allocated},
      {"beam_allocator_free", max(allocated - used, 0)}
    ] ++ mapped() ++ native() ++ malloc() ++ resident()
  end

  # Everything the BEAM has mapped for its allocators, including freed
  # segments kept in its segment cache (`+MMmcs`), which no allocator reports.
  defp mapped do
    case :erlang.system_info({:allocator, :erts_mmap}) do
      [{:default_mmap, props} | _] ->
        case props[:os][:sizes][:used] do
          bytes when is_integer(bytes) -> [{"beam_mapped", bytes}]
          _ -> []
        end

      _ ->
        []
    end
  rescue
    _ -> []
  end

  @doc """
  Return free C-allocator memory to the operating system. glibc only gives
  back the top of each arena on its own; pages freed in the middle by native
  work (Parquet encoding, manifest JSON, S3 bodies) stay resident until
  trimmed. Takes a few milliseconds on a dirty scheduler; a no-op elsewhere.
  """
  def trim do
    Codec.native_malloc_trim()
    :ok
  rescue
    _ -> :ok
  end

  @doc "Live Rust heap bytes per NIF library; libraries that are not loaded are omitted."
  def native do
    for {name, module} <- @natives, bytes = native_bytes(module), is_integer(bytes), do: {"native_#{name}", bytes}
  end

  defp native_bytes(module) do
    module.native_allocated_bytes()
  rescue
    _ -> nil
  end

  defp malloc do
    case Codec.native_malloc_stats() do
      {_system, in_use, free} -> [{"malloc_in_use", in_use}, {"malloc_free", free}]
      nil -> []
    end
  rescue
    _ -> []
  end

  @doc "Resident memory (`rss`, `rss_anon`) from /proc; empty off Linux."
  def resident do
    case File.read("/proc/self/status") do
      {:ok, status} ->
        for {field, kind} <- [{"VmRSS", "rss"}, {"RssAnon", "rss_anon"}],
            [_, kb] <- [Regex.run(~r/^#{field}:\s+(\d+) kB$/m, status)],
            do: {kind, String.to_integer(kb) * 1024}

      _ ->
        []
    end
  end

  # Blocks in use and carrier bytes held, summed over every allocator instance.
  defp allocators do
    for type <- @allocators, instance <- instances(type), reduce: {0, 0} do
      {used, allocated} ->
        {blocks, carriers} = instance_sizes(instance)
        {used + blocks, allocated + carriers}
    end
  end

  defp instances(type) do
    case :erlang.system_info({:allocator_sizes, type}) do
      list when is_list(list) -> for {:instance, _, props} <- list, do: props
      _ -> []
    end
  end

  defp instance_sizes(props) do
    for {kind, values} when kind in [:mbcs, :sbcs, :mbcs_pool] <- props, reduce: {0, 0} do
      {blocks, carriers} -> {blocks + block_bytes(values), carriers + carrier_bytes(values)}
    end
  end

  defp block_bytes(values) do
    for {:blocks, types} <- values, {_type, sizes} <- types, {:size, current, _, _} <- sizes, reduce: 0 do
      total -> total + current
    end
  end

  defp carrier_bytes(values) do
    Enum.find_value(values, 0, fn
      {:carriers_size, current, _, _} -> current
      {:carriers_size, current} -> current
      _ -> nil
    end)
  end

  @doc "ETS memory per table name, summed over tables sharing a name, largest first."
  @spec ets() :: [{String.t(), non_neg_integer()}]
  def ets do
    words = :erlang.system_info(:wordsize)

    :ets.all()
    |> Enum.reduce(%{}, fn table, acc ->
      case {:ets.info(table, :name), :ets.info(table, :memory)} do
        {name, memory} when is_atom(name) and is_integer(memory) ->
          Map.update(acc, table_name(name), memory * words, &(&1 + memory * words))

        _ ->
          acc
      end
    end)
    |> Enum.sort_by(fn {_name, bytes} -> -bytes end)
  end

  defp table_name(name), do: name |> Atom.to_string() |> String.replace_prefix("Elixir.", "")

  @groups ~w(manifest_owner append_buffer ingest_flush query maintenance http_connection other)
  @labelled [:manifest_owner, :append_buffer, :ingest_flush, :query, :maintenance]

  @doc """
  Process memory (heap, stack, mailbox) by a fixed set of groups, from process
  labels. Referenced binaries are reported once, under `binary`, not per group:
  listing them per process would cost as much as the scrape is meant to watch.
  """
  @spec processes() :: [{String.t(), non_neg_integer()}]
  def processes do
    totals = Map.new(@groups, &{&1, 0})

    Process.list()
    |> Enum.reduce(totals, fn pid, acc ->
      case :erlang.process_info(pid, [:memory, {:dictionary, :"$process_label"}]) do
        [{:memory, memory}, {_label_key, label}] -> Map.update!(acc, group(label), &(&1 + memory))
        _exited -> acc
      end
    end)
    |> Enum.sort_by(fn {_group, bytes} -> -bytes end)
  end

  defp group({:pulse, group}) when group in @labelled, do: Atom.to_string(group)
  defp group({:thousand_island, :connection, _handler}), do: "http_connection"
  defp group(_label), do: "other"
end
