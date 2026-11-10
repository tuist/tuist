defmodule Pulse.Storage.S3.ManifestCache do
  @moduledoc """
  Lock-free in-memory cache of manifests, keyed by `(tenant, signal)`.

  The query path is the hot path — every `Pulse.Storage.S3.query/2` call
  looks up its manifest before deciding which segments to fetch. This
  cache sits on a public ETS table with `read_concurrency: true`, so
  concurrent queries never contend with each other or with the
  ManifestOwner that owns writes.

  Refreshes replace only their starting ETag. Publications also compare their
  starting ETag, invalidating on an intervening snapshot rather than guessing
  an order for opaque tags. Delayed reads and maintenance responses must not
  overwrite a newer acknowledged publication. Both paths remain lock-free.

  ETS stores each manifest as its encoded wire binary, not the decoded
  struct. ETS flattens every term it stores, which expands the name and
  label dictionaries that decoded segments share; for metrics the flattened
  struct is about 50 times the wire size, and flat (unretained) manifests grow
  with every append. The refcounted binary is stored once without copying,
  and each reader decodes a compact, sharing copy. Use `info/2` or `token/2`
  when only the version, ETag or generation is needed.

  The cache is disposable and bounded by encoded payload bytes
  (`PULSE_MANIFEST_CACHE_MAX_BYTES`). A sweep every second drops the least
  recently used roots above the bound, always keeping the most recently used
  one. Under node memory pressure (`Pulse.MemoryPressure`) it also drops roots
  unused for 30 seconds; hot roots stay, since their owners republish them.
  An evicted root leaves the same generation fence as `drop/2`, so the next
  reader reloads it through its owner like any cold miss.

  The entry shape carries the manifest struct, the ETag it was fetched
  with (used on the next conditional GET to short-circuit an unchanged
  read), and the monotonic timestamp of the last refresh (used by the
  owner to decide whether a refresh is due).
  """

  use Pulse.Runtime.GenServer

  alias Pulse.Runtime.GenServer
  alias Pulse.Storage.S3.JournalManifest
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.Retention

  @table __MODULE__
  @access Module.concat(__MODULE__, Access)
  @default_max_bytes 134_217_728
  @sweep_ms 1000
  @pressure_idle_ms 30_000

  @type entry :: %{
          manifest: Manifest.t(),
          etag: String.t(),
          refreshed_at_mono: integer()
        }

  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Every table operation goes through the current runtime's instance name.
  defp table, do: Pulse.Runtime.table(@table)
  defp access, do: Pulse.Runtime.table(@access)

  @doc """
  Look up the cached manifest for one `(tenant, signal)`. Returns
  `nil` when nothing is cached yet — the caller is responsible for
  populating it.

  This is the hot path. A single `:ets.lookup/2` under
  `read_concurrency: true` — no message passing, no locks under load.
  """
  @spec get(String.t(), String.t()) :: entry() | nil
  def get(tenant, signal) when is_binary(tenant) and is_binary(signal) do
    {entry, _token} = snapshot(tenant, signal)
    entry
  end

  @doc false
  def snapshot(tenant, signal) do
    case :ets.lookup(table(), {tenant, signal}) do
      [{_, %{invalidated?: true, token: token}}] ->
        {nil, token}

      [{_, entry}] ->
        used(tenant, signal)
        {expand(entry), entry.token}

      [] ->
        {nil, nil}
    end
  end

  # Last-use order for eviction (reads and installs). A separate table, because entries are
  # maps that cannot be updated in place without copying their payload.
  defp used(tenant, signal) do
    :ets.insert(
      access(),
      {{tenant, signal}, :erlang.unique_integer([:monotonic, :positive]), System.monotonic_time(:millisecond)}
    )
  rescue
    ArgumentError -> true
  end

  # Cached payloads were produced by `Manifest.encode/1` (or validated fetched
  # bodies), so decoding cannot fail.
  defp expand(%{payload: payload} = entry) do
    {:ok, manifest} = Manifest.decode(payload)
    entry |> Map.delete(:payload) |> Map.put(:manifest, manifest)
  end

  @doc """
  The cached entry's `{version, etag, token}` without copying its manifest.
  `:ets.lookup/2` copies the whole decoded manifest into the caller's heap;
  flat manifests grow with every segment, so ingest and publication paths
  that only need these fields must use this instead. Invalidated or missing
  entries return `{nil, nil, token}`.
  """
  def info(tenant, signal) do
    key = {tenant, signal}

    case :ets.select(table(), [
           {{key, %{invalidated?: true, token: :"$1"}}, [], [{{nil, nil, :"$1"}}]},
           {{key, %{version: :"$1", etag: :"$2", token: :"$3"}}, [], [{{:"$1", :"$2", :"$3"}}]}
         ]) do
      [info | _] -> info
      [] -> {nil, nil, nil}
    end
  end

  @doc """
  Mark an unchanged cached manifest fresh (after a 304) without re-encoding
  or copying it, only while `token` is still the cached generation.
  """
  def touch(tenant, signal, token) do
    key = {tenant, signal}

    with [{^key, %{token: ^token, payload: _} = entry}] <- :ets.lookup(table(), key) do
      touched = %{entry | refreshed_at_mono: System.monotonic_time(:millisecond)}
      :ets.select_replace(table(), [{{key, %{token: token}}, [], [{:const, {key, touched}}]}])
    end

    :ok
  end

  @doc "Cache generation token, without copying the manifest."
  def token(tenant, signal), do: elem(info(tenant, signal), 2)

  @doc "Install a read only if its exact cache generation is still current."
  def put_snapshot(tenant, signal, manifest, etag, token) do
    object = {{tenant, signal}, entry(tenant, signal, manifest, etag)}

    if token == nil do
      :ets.insert_new(table(), object)
    else
      :ets.select_replace(table(), [{{{tenant, signal}, %{token: token}}, [], [{:const, object}]}])
    end

    :ok
  end

  @doc """
  Seed a manifest entry unconditionally. Production refresh/publication paths
  use the conditional APIs below; this is useful for owned fixtures.
  """
  @spec put(String.t(), String.t(), Manifest.t(), String.t()) :: :ok
  def put(tenant, signal, manifest, etag) when is_binary(tenant) and is_binary(signal) and is_binary(etag) do
    :ets.insert(table(), {{tenant, signal}, entry(tenant, signal, manifest, etag)})
    :ok
  end

  @doc "Cache a reader snapshot only if no other publication replaced its starting ETag."
  def put_if_current(tenant, signal, manifest, etag, expected_etag) do
    object = {{tenant, signal}, entry(tenant, signal, manifest, etag)}

    if is_nil(expected_etag) do
      :ets.insert_new(table(), object)
    else
      :ets.select_replace(table(), [{{{tenant, signal}, %{etag: expected_etag}}, [], [{:const, object}]}])
    end

    :ok
  end

  @doc "Install against the predecessor ETag and pre-I/O publication_base generation, or invalidate."
  def publish(tenant, signal, manifest, etag, expected_etag, base) do
    object = {{tenant, signal}, entry(tenant, signal, manifest, etag)}

    replaced =
      case base do
        {:warm, token} ->
          :ets.select_replace(table(), [
            {{{tenant, signal}, %{etag: expected_etag, token: token}}, [], [{:const, object}]}
          ])

        {:cold, _token} ->
          0
      end

    # Cold publications may install only the exact empty generation observed
    # BEFORE their CAS, never an absence created by another writer afterwards.
    if replaced == 0 and not install_cold(object, base), do: drop(tenant, signal)
    :ok
  end

  @doc false
  def publication_base(tenant, signal) do
    case info(tenant, signal) do
      {nil, _etag, token} -> {:cold, token}
      {_version, _etag, token} -> {:warm, token}
    end
  end

  defp install_cold(object, {:cold, nil}), do: :ets.insert_new(table(), object)

  defp install_cold({key, _entry} = object, {:cold, token}) do
    :ets.select_replace(table(), [{{key, %{invalidated?: true, token: token}}, [], [{:const, object}]}]) == 1
  end

  defp install_cold(_object, {:warm, _token}), do: false

  defp entry(tenant, signal, manifest, etag) do
    {manifest, payload} = wire(manifest)
    used(tenant, signal)

    entry = %{
      payload: payload,
      # Root size for node-local gauges; paged and managed roots list only
      # their tail. Paged roots also know every segment their pages reference.
      segments: length(manifest.segments),
      referenced: JournalManifest.referenced(manifest),
      stored: JournalManifest.referenced_bytes(manifest),
      version: manifest.version,
      etag: etag,
      token: make_ref(),
      refreshed_at_mono: System.monotonic_time(:millisecond)
    }

    entry =
      if manifest.version == 3 do
        previous = :ets.select(table(), [{{{tenant, signal}, %{etag: etag, statistics: :"$1"}}, [], [:"$1"]}])

        statistics =
          case previous do
            [statistics] -> statistics
            [] -> Retention.metadata_stats(manifest)
          end

        Map.put(entry, :statistics, statistics)
      else
        entry
      end

    entry
  end

  # Callers that already hold the exact encoded bytes (a publication payload or
  # a validated fetched body) pass `{manifest, payload}` to avoid re-encoding.
  defp wire({%Manifest{} = manifest, payload}) when is_binary(payload), do: {manifest, payload}
  defp wire(%Manifest{} = manifest), do: {manifest, IO.iodata_to_binary(Manifest.encode(manifest))}

  @doc """
  Per signal, summed over tenants without copying payloads: listed root
  segments (`0`), encoded root bytes (`1`), referenced segments (`2`) and the
  number of roots per format (`"flat"`, `"paged"`, `"retention"`).
  """
  def sizes do
    :ets.select(table(), [
      {{{:_, :"$1"}, %{payload: :"$2", segments: :"$3", referenced: :"$4", version: :"$5"}}, [],
       [{{:"$1", :"$3", {:byte_size, :"$2"}, :"$4", :"$5"}}]}
    ])
    |> Enum.reduce(%{}, fn {signal, segments, bytes, referenced, version}, acc ->
      format =
        case version do
          4 -> "paged"
          3 -> "retention"
          _ -> "flat"
        end

      totals = Map.get(acc, signal, %{0 => 0, 1 => 0, 2 => 0})

      totals =
        totals
        |> Map.update!(0, &(&1 + segments))
        |> Map.update!(1, &(&1 + bytes))
        |> Map.update!(2, &(&1 + referenced))
        |> Map.update(format, 1, &(&1 + 1))

      Map.put(acc, signal, totals)
    end)
  rescue
    ArgumentError -> %{}
  end

  @doc """
  Referenced segment bytes per signal and age bucket (`"0-30d"`, `"30-90d"`,
  `"90d+"`, by record time), plus segments of unknown size, summed over cached
  roots without storage I/O. A page reference's bytes are spread evenly over
  its time range.
  """
  def stored_bytes(now_ns \\ System.os_time(:nanosecond)) do
    :ets.select(table(), [{{{:_, :"$1"}, %{stored: :"$2"}}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.reduce(%{}, fn {signal, {spans, unknown}}, acc ->
      totals = Map.get(acc, signal, %{"0-30d" => 0, "30-90d" => 0, "90d+" => 0, unknown: 0})
      totals = Enum.reduce(spans, %{totals | unknown: totals.unknown + unknown}, &add_span(&1, &2, now_ns))
      Map.put(acc, signal, totals)
    end)
  rescue
    ArgumentError -> %{}
  end

  @day_ns 86_400_000_000_000
  # Walks the span from its newest record down through the buckets. Shares are
  # differences of cumulative floors, so they always add up to `bytes`.
  defp add_span({min_ts, max_ts, bytes}, totals, now_ns) do
    width = max(max_ts - min_ts + 1, 1)

    [{"0-30d", now_ns - 30 * @day_ns}, {"30-90d", now_ns - 90 * @day_ns}, {"90d+", nil}]
    |> Enum.reduce({totals, max_ts, 0}, fn {bucket, floor}, {totals, upper, covered} ->
      lower = if floor, do: max(min_ts, floor), else: min_ts
      covered_after = covered + max(upper - lower + 1, 0)
      share = div(bytes * covered_after, width) - div(bytes * covered, width)
      {Map.update!(totals, bucket, &(&1 + share)), min(upper, lower - 1), covered_after}
    end)
    |> elem(0)
  end

  @doc "Small node-local summaries for fixed-cardinality retention gauges, without storage I/O."
  def retention_statistics do
    :ets.select(table(), [{{:_, %{statistics: :"$1"}}, [], [:"$1"]}])
  rescue
    ArgumentError -> []
  end

  @doc "Tenants observed locally through ingest or queries, without listing segment objects."
  def tenants(signal) when is_binary(signal) do
    :ets.select(table(), [{{{:"$1", signal}, :_}, [], [:"$1"]}]) |> Enum.sort()
  end

  @doc "Bounded local scope discovery; the opaque ETS continuation contains no root values."
  def scopes_page(cursor, limit) when limit in 1..16 do
    scope_scan(cursor, limit, [])
  rescue
    ArgumentError -> {[], nil}
  end

  defp scope_scan(cursor, 0, acc), do: {Enum.reverse(acc), cursor}

  defp scope_scan(cursor, remaining, acc) do
    # The continuation embeds its chunk size. Keep it at one so callers may
    # shrink their queue allowance without receiving an oversized next chunk.
    result = if cursor == nil, do: :ets.select(table(), [{{:"$1", :_}, [], [:"$1"]}], 1), else: :ets.select(cursor)

    case result do
      :"$end_of_table" -> {Enum.reverse(acc), nil}
      {scopes, :"$end_of_table"} -> {Enum.reverse(scopes ++ acc), nil}
      {[scope], next} -> scope_scan(next, remaining - 1, [scope | acc])
    end
  end

  @doc "Drop a cached entry — used on tenant deletion or forced cache flush."
  @spec drop(String.t(), String.t()) :: :ok
  def drop(tenant, signal) when is_binary(tenant) and is_binary(signal) do
    # Keep a generation fence, not a manifest. Deleting the key would allow
    # a cold reader or delayed publisher from before the ACK to reinsert it.
    :ets.insert(table(), {{tenant, signal}, %{invalidated?: true, token: make_ref()}})
    :ok
  end

  @doc false
  @spec reset() :: :ok
  def reset do
    if :ets.info(table()) != :undefined do
      :ets.delete_all_objects(table())
    end

    if :ets.info(access()) != :undefined, do: :ets.match_delete(access(), {{:_, :_}, :_, :_})

    :ok
  end

  @doc "The configured byte bound on cached root payloads."
  def max_bytes do
    case :ets.lookup(access(), :max_bytes) do
      [{:max_bytes, bytes}] -> bytes
      [] -> configured_max_bytes()
    end
  rescue
    ArgumentError -> configured_max_bytes()
  end

  defp configured_max_bytes,
    do: Keyword.get(Pulse.Runtime.get_env(:pulse, __MODULE__, []), :max_bytes, @default_max_bytes)

  @doc """
  Evict least recently used roots until cached payloads fit `target` bytes,
  and every root last used before `idle_before` (monotonic milliseconds), keeping
  the most recently used root. Returns `{evicted, evicted_bytes}`.
  """
  def evict(target, idle_before \\ nil) when is_integer(target) and target >= 0 do
    last_use =
      Map.new(:ets.select(access(), [{{{:"$1", :"$2"}, :"$3", :"$4"}, [], [{{{{:"$1", :"$2"}}, {{:"$3", :"$4"}}}}]}]))

    entries =
      :ets.select(table(), [
        {{:"$1", %{payload: :"$2", token: :"$3"}}, [], [{{:"$1", {:byte_size, :"$2"}, :"$3"}}]}
      ])
      |> Enum.map(fn {key, bytes, token} -> {Map.get(last_use, key, {0, 0}), key, bytes, token} end)
      |> Enum.sort()

    total = Enum.reduce(entries, 0, fn {_, _, bytes, _}, acc -> acc + bytes end)
    # The most recently used root stays even when it alone exceeds the bound.
    candidates = Enum.drop(entries, -1)
    evict(candidates, total, target, idle_before, {0, 0})
  rescue
    ArgumentError -> {0, 0}
  end

  defp evict([{{_, used_at}, key, bytes, token} | rest], total, target, idle_before, {count, evicted} = result) do
    if total > target or (idle_before != nil and used_at < idle_before) do
      fence = {key, %{invalidated?: true, token: make_ref()}}

      # Only the observed generation; a concurrent refresh or publication wins.
      if :ets.select_replace(table(), [{{key, %{token: token}}, [], [{:const, fence}]}]) == 1 do
        :ets.delete(access(), key)
        evict(rest, total - bytes, target, idle_before, {count + 1, evicted + bytes})
      else
        evict(rest, total, target, idle_before, result)
      end
    else
      # Entries are ordered by last use, so no later one is idle either.
      result
    end
  end

  defp evict([], _total, _target, _idle_before, result), do: result

  @impl true
  def init(opts) do
    ensure_table()
    max = Keyword.get(opts, :max_bytes, configured_max_bytes())
    :ets.insert(access(), {:max_bytes, max})
    interval = Keyword.get(opts, :sweep_interval_ms, @sweep_ms)
    state = %{max_bytes: max, interval: interval}
    schedule(state)
    {:ok, state}
  end

  @impl true
  def handle_info(:sweep, state) do
    # Under memory pressure also drop roots no reader or publication used for
    # 30 s. Hot roots stay: their owner republishes them on every flush, so
    # evicting them frees nothing and makes every reader reload.
    idle_before =
      if Pulse.MemoryPressure.active?(), do: System.monotonic_time(:millisecond) - @pressure_idle_ms

    sweep(state.max_bytes, idle_before)
    schedule(state)
    {:noreply, state}
  end

  defp sweep(target, idle_before) do
    case evict(target, idle_before) do
      {0, _} -> :ok
      {count, bytes} -> Pulse.SelfMetrics.manifest_cache_evicted(count, bytes)
    end
  end

  defp schedule(%{interval: :infinity}), do: :ok
  defp schedule(%{interval: ms}), do: Process.send_after(self(), :sweep, ms)

  @doc false
  def ensure_table do
    case :ets.info(table()) do
      :undefined ->
        :ets.new(table(), [
          :named_table,
          :set,
          :public,
          {:read_concurrency, true}
        ])

      _ ->
        :ok
    end

    if :ets.info(access()) == :undefined,
      do: :ets.new(access(), [:named_table, :set, :public, {:write_concurrency, true}])

    table()
  end
end
