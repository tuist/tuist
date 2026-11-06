defmodule Pulse.MemoryPressure do
  @moduledoc """
  Node-local memory-pressure state that sheds disposable work before the
  container is OOM-killed, as other observability backends do: idle caches
  are evicted, new interactive queries are refused with a retryable overload
  error, and ingest keeps its own admission slots. Acknowledged data is never
  dropped.

  Every second it compares resident memory with the node limit. Pressure turns
  on at `high` (default 85%) of the limit and off once memory has stayed below
  `low` (10 points lower) for `hold_ms` (10 s). Query bursts move resident
  memory by tens of megabytes within a second, so level hysteresis alone
  flaps. The limit is either a
  fixed byte count or the container's cgroup limit, re-read every 15 seconds
  so an in-place resize takes effect without a restart. Slot counts derived at
  boot (`Pulse.ResourceBudget`) still need a restart to change.

  State lives in a public ETS table, so admission checks never message this
  process. When the monitor is not running, pressure is never reported.
  """
  use Pulse.Runtime.GenServer

  alias Pulse.Runtime.GenServer
  alias Pulse.Storage.S3.ManifestCache
  alias Pulse.Storage.S3.ObjectCache

  @table __MODULE__
  @interval_ms 1000
  @limit_refresh_ms 15_000

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  defp table, do: Pulse.Runtime.table(@table)

  @doc "Whether this node is under memory pressure."
  def active? do
    match?([{:active, true}], :ets.lookup(table(), :active))
  rescue
    ArgumentError -> false
  end

  @doc "`{used_bytes, limit_bytes}` from the last sample; nil limit when unknown or disabled."
  def stats do
    case :ets.lookup(table(), :sample) do
      [{:sample, used, limit}] -> {used, limit}
      [] -> {0, nil}
    end
  rescue
    ArgumentError -> {0, nil}
  end

  @impl true
  def init(opts) do
    config = Keyword.merge(Pulse.Runtime.get_env(:pulse, __MODULE__, []), opts)
    :ets.new(table(), [:named_table, :public, :set, read_concurrency: true])
    :ets.insert(table(), [{:active, false}, {:sample, 0, nil}])
    high = Keyword.get(config, :high_percent, 85)

    state = %{
      limit_source: Keyword.get(config, :limit),
      usage: Keyword.get(config, :usage, &resident_bytes/0),
      high: high / 100,
      low: max(high - 10, 1) / 100,
      interval: Keyword.get(config, :interval_ms, @interval_ms),
      limit_refresh: Keyword.get(config, :limit_refresh_ms, @limit_refresh_ms),
      limit: nil,
      limit_read_at: nil,
      hold: Keyword.get(config, :hold_ms, 10_000),
      below_since: nil,
      active?: false
    }

    send(self(), :sample)
    {:ok, state}
  end

  @impl true
  def handle_info(:sample, state) do
    state = refresh_limit(state)
    used = state.usage.()
    now = System.monotonic_time(:millisecond)
    state = next_state(state, used, now)
    :ets.insert(table(), [{:active, state.active?}, {:sample, used, state.limit}])
    Process.send_after(self(), :sample, state.interval)
    {:noreply, state}
  end

  defp next_state(%{limit: limit, high: high, low: low} = state, used, now) when is_integer(limit) and high > 0 do
    cond do
      not state.active? and used >= high * limit -> enter(state, true)
      not state.active? -> state
      used >= low * limit -> %{state | below_since: nil}
      state.below_since == nil -> %{state | below_since: now}
      now - state.below_since >= state.hold -> enter(state, false)
      true -> state
    end
  end

  defp next_state(%{active?: true} = state, _used, _now), do: enter(state, false)
  defp next_state(state, _used, _now), do: state

  defp enter(state, active?) do
    transition(active?)
    %{state | active?: active?, below_since: nil}
  end

  defp transition(true) do
    Pulse.SelfMetrics.memory_pressure(:on)
    # Drop idle manifest roots now rather than on the next sweep.
    if pid = Pulse.Runtime.whereis(ManifestCache), do: send(pid, :sweep)
    ObjectCache.clear_memory()
  end

  defp transition(false), do: Pulse.SelfMetrics.memory_pressure(:off)

  defp refresh_limit(%{limit_read_at: at, limit_refresh: refresh} = state) do
    now = System.monotonic_time(:millisecond)

    if at == nil or now - at >= refresh,
      do: %{state | limit: read_limit(state.limit_source), limit_read_at: now},
      else: state
  end

  defp read_limit(nil), do: nil
  defp read_limit(bytes) when is_integer(bytes) and bytes > 0, do: bytes

  defp read_limit(:cgroup) do
    case Pulse.ResourceBudget.cgroup_limit_mb() do
      mb when is_integer(mb) -> mb * 1_048_576
      nil -> nil
    end
  end

  defp read_limit(fun) when is_function(fun, 0), do: fun.()

  # Resident memory is what the container limit charges for; the BEAM's own
  # total misses native heaps and cached allocator segments.
  defp resident_bytes do
    case List.keyfind(Pulse.MemoryStats.resident(), "rss", 0) do
      {"rss", bytes} -> bytes
      nil -> :erlang.memory(:total)
    end
  end
end
