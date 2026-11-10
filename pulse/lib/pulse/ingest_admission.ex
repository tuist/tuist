defmodule Pulse.IngestAdmission do
  @moduledoc """
  Node-local bound on concurrently processed ingest requests, shared fairly
  between signals.

  Per-request limits cap one request's body, records and heap, but not how
  many run at once: an exporter's retry backlog after a restart can otherwise
  decode many large batches in parallel and exhaust the node's memory. At most
  `:max_concurrent` (`PULSE_INGEST_MAX_CONCURRENT_REQUESTS`) requests hold a
  slot; further requests are refused with a retryable 429 instead, and
  exporters back off and retry, possibly on another instance.

  ## Fairness

  Slots are split by signal class (`:metrics`, `:logs`, `:traces`). Each class
  owns `:reserved_per_signal` slots (`PULSE_INGEST_RESERVED_REQUESTS_PER_SIGNAL`,
  default an eighth of the slots, at least one with three or more slots) that
  no other class can take; the rest form a
  shared pool any class may borrow from. A remote-write replay can therefore
  hold its reserve plus the whole shared pool, but never the reserves that keep
  logs and traces admitted. Every counter is updated atomically, so the global
  bound and every reserve are exact.

  Within a signal, slots are shared between tenants (the `X-Scope-OrgID`
  the request names, before authentication). A tenant is *active* for a
  signal while it holds a slot or has asked for one in the last
  `:tenant_window_ms` (5 s). Each active tenant may always fill its equal share
  of the signal's usable slots (reserve plus shared pool). Above that share it
  may only borrow while at least one usable slot stays free for every other
  active tenant, so a flooding tenant cannot take the slot another tenant's
  retry needs. A lone tenant can use the whole share. The active count is
  recomputed at most every `:tenant_refresh_ms` (500 ms), so the per-request
  cost does not grow with tenants. These per-tenant checks are best effort under
  racing requests; the global bound and signal reserves stay exact. At most
  1024 tenants per signal are tracked per node; the rest share one bucket.

  ## Pending publication handoff

  A slot bounds decoding memory. Once a request's records are queued in a
  bounded ingest buffer, it only waits for the durable segment PUT and manifest
  CAS. `handoff/1` then moves the request from its slot into a node-wide
  pending budget charged by its estimated record bytes (`:max_pending_bytes`,
  `PULSE_INGEST_MAX_PENDING_BYTES`), freeing the slot for the next request.
  When the budget is full the request keeps its slot while it waits, exactly
  as without handoff, so node memory stays bounded by slots plus the budget.
  The acknowledgment is still sent only after durable publication.

  A slot or pending charge belongs to the process handling the request. HTTP/1.1
  connection processes handle one request at a time, so a request that raises
  before its response does not leak: the connection's next request replaces
  it, and everything is released when the process exits. This is a disposable
  per-instance optimization, never cluster state.
  """
  use Pulse.Runtime.GenServer

  alias Pulse.Runtime.GenServer

  @table __MODULE__
  @default_max 32
  @default_max_pending_bytes 64 * 1024 * 1024
  @signals [:metrics, :logs, :traces]
  @max_tenants 1024
  @default_tenant_window_ms 5_000
  @default_tenant_refresh_ms 500

  def signals, do: @signals

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  defp table, do: Pulse.Runtime.table(@table)

  @doc """
  Take this process's slot for `signal` on behalf of `tenant`, or
  `{:error, :ingest_overloaded}` when neither the signal's reserve nor the
  shared pool has room, or when `tenant` is above its fair share of the signal.

  `limited` names a tenant whose credentials have verified. When
  `Pulse.TenantLimits` gives it an `ingest_max_concurrent` bound, the request
  also takes one of that tenant's node-wide slots (across signals) or fails
  with `:tenant_concurrency`; it is released with the slot, including at
  `handoff/1`.
  """
  @spec acquire(atom(), String.t(), String.t() | nil) :: :ok | {:error, :ingest_overloaded | :tenant_concurrency}
  def acquire(signal \\ :metrics, tenant \\ "default", limited \\ nil) when signal in @signals and is_binary(tenant) do
    pid = self()
    table = table()

    case :ets.lookup(table, {:held, pid}) do
      [{_, {:slot, _signal, _pool, _tenant}}] ->
        :ok

      held ->
        # A request that raised after handoff leaves its pending charge behind.
        if held != [], do: release(pid)
        take(table, pid, signal, tenant, limited)
    end
  rescue
    # Not started (some test runtimes and tools): never fail ingest.
    ArgumentError -> :ok
  end

  defp take(table, pid, signal, tenant, limited) do
    limits = limits()
    now = System.monotonic_time(:millisecond)
    key = tenant_key(table, signal, tenant, now)
    limit = tenant_limit(limited)

    case pool(table, signal, key, limits, limit, now) do
      pool when pool in [:reserved, :shared] ->
        if limit, do: :ets.insert(table, {{:limited, pid}, limited})
        :ets.insert(table, {{:held, pid}, {:slot, signal, pool, key}})
        :ets.update_counter(table, {:in_flight, signal}, {2, 1}, {{:in_flight, signal}, 0})
        :ets.update_counter(table, key, {2, 1}, {key, 0, now})
        count(table, signal, :admitted)
        GenServer.cast(__MODULE__, {:monitor, pid})
        :ok

      :tenant_concurrency ->
        Pulse.SelfMetrics.admission_rejection(:ingest, :tenant_concurrency)
        {:error, :tenant_concurrency}

      reason ->
        if reason == :tenant_limited, do: count(table, signal, :tenant_limited)
        count(table, signal, :rejected)
        {:error, :ingest_overloaded}
    end
  end

  # The fair share comes first, then the configured tenant bound, then the
  # signal's reserve and the shared pool; a refused pool undoes the tenant claim.
  defp pool(table, signal, key, limits, limit, now) do
    cond do
      not within_share?(table, signal, key, limits, now) -> :tenant_limited
      not claim_tenant(table, limit) -> :tenant_concurrency
      claim(table, {:reserved, signal}, limits.reserved) -> :reserved
      claim(table, :shared, limits.shared) -> :shared
      true -> unclaim_tenant(table, limit)
    end
  end

  # Configured bounds (`Pulse.TenantLimits`) count `{{:limit, tenant}, held}`
  # across signals; rows of tenants holding nothing are deleted on release.
  defp tenant_limit(nil), do: nil

  defp tenant_limit(tenant) do
    case Pulse.TenantLimits.get(tenant, :ingest_max_concurrent) do
      nil -> nil
      max -> {{:limit, tenant}, max}
    end
  end

  defp claim_tenant(_table, nil), do: true

  defp claim_tenant(table, {key, max}) do
    # A refused claim leaves the counter as it was; a zero bound leaves a 0 row.
    claim(table, key, max) || (drop_idle_limit(table, key) && false)
  end

  defp unclaim_tenant(_table, nil), do: nil

  defp unclaim_tenant(table, {key, _max}) do
    release_limit(table, key)
    nil
  end

  defp release_limit(table, key) do
    if :ets.update_counter(table, key, {2, -1}, {key, 1}) <= 0, do: drop_idle_limit(table, key)
  end

  defp drop_idle_limit(table, key), do: :ets.select_delete(table, [{{key, 0}, [], [true]}])

  # Rows are `{{:tenant, signal, tenant}, held_slots, last_demand_ms}`. A new
  # tenant takes a tracking credit; beyond the cap tenants share one bucket.
  defp tenant_key(table, signal, tenant, now) do
    key = {:tenant, signal, tenant}

    cond do
      :ets.update_element(table, key, {3, now}) ->
        key

      claim(table, {:tracked, signal}, @max_tenants) ->
        if not :ets.insert_new(table, {key, 0, now}), do: :ets.update_counter(table, {:tracked, signal}, {2, -1})
        key

      true ->
        overflow = {:tenant, signal, :overflow}
        if not :ets.update_element(table, overflow, {3, now}), do: :ets.insert_new(table, {overflow, 0, now})
        overflow
    end
  end

  # Below its equal share a tenant is limited only by the pools. Above it, a
  # tenant must leave one usable slot free for each other active tenant.
  defp within_share?(table, signal, key, limits, now) do
    active = active_tenants(table, signal, now)
    usable = limits.reserved + limits.shared
    held = counter(table, key)

    if held < max(1, div(usable + active - 1, active)) do
      true
    else
      free =
        max(0, limits.reserved - counter(table, {:reserved, signal})) + max(0, limits.shared - counter(table, :shared))

      # With nothing free the pools refuse it anyway, as plain capacity;
      # `tenant_limited` means free slots existed but were kept for others.
      free == 0 or free >= active
    end
  end

  # Recomputed by whichever request finds it stale; racing recomputations agree.
  defp active_tenants(table, signal, now) do
    config = Pulse.Runtime.get_env(:pulse, __MODULE__, [])
    refresh = Keyword.get(config, :tenant_refresh_ms, @default_tenant_refresh_ms)

    case :ets.lookup(table, {:active, signal}) do
      [{_, active, at}] when now - at < refresh ->
        active

      _ ->
        cutoff = now - Keyword.get(config, :tenant_window_ms, @default_tenant_window_ms)
        # The untracked overflow bucket holds no tracking credit; keep it.
        idle = [{{{:tenant, signal, :"$2"}, 0, :"$1"}, [{:<, :"$1", cutoff}, {:"=/=", :"$2", :overflow}], [true]}]
        pruned = :ets.select_delete(table, idle)
        if pruned > 0, do: :ets.update_counter(table, {:tracked, signal}, {2, -pruned}, {{:tracked, signal}, 0})

        active =
          max(
            1,
            :ets.select_count(table, [
              {{{:tenant, signal, :_}, :"$1", :"$2"}, [{:orelse, {:>, :"$1", 0}, {:>, :"$2", cutoff}}], [true]}
            ])
          )

        :ets.insert(table, {{:active, signal}, active, now})
        active
    end
  end

  defp claim(table, key, limit) do
    if :ets.update_counter(table, key, {2, 1}, {key, 0}) <= limit do
      true
    else
      :ets.update_counter(table, key, {2, -1})
      false
    end
  end

  @doc """
  Move this process from its slot to the pending-publication budget, charging
  `bytes`. Without a slot, or when the budget is full, nothing changes.
  """
  @spec handoff(non_neg_integer()) :: :ok
  def handoff(bytes) when is_integer(bytes) and bytes >= 0 do
    table = table()
    pid = self()

    with [{_, {:slot, signal, _pool, _tenant}}] <- :ets.lookup(table, {:held, pid}),
         true <- claim_bytes(table, bytes) do
      free_slot(table, pid)
      :ets.insert(table, {{:held, pid}, {:pending, signal, bytes}})
      count(table, signal, :handed_off)
    end

    :ok
  rescue
    ArgumentError -> :ok
  end

  defp claim_bytes(table, bytes) do
    if :ets.update_counter(table, :pending_bytes, {2, bytes}, {:pending_bytes, 0}) <= max_pending_bytes() do
      true
    else
      :ets.update_counter(table, :pending_bytes, {2, -bytes})
      false
    end
  end

  @doc "Release this process's slot or pending charge, if it holds one."
  def release(pid \\ self()) do
    table = table()

    case :ets.take(table, {:held, pid}) do
      [{_, {:slot, signal, pool, tenant}}] ->
        release_slot(table, pid, signal, pool, tenant)

      [{_, {:pending, _signal, bytes}}] ->
        :ets.update_counter(table, :pending_bytes, {2, -bytes})

      [] ->
        :ok
    end

    :ok
  rescue
    ArgumentError -> :ok
  end

  defp free_slot(table, pid) do
    [{_, {:slot, signal, pool, tenant}}] = :ets.lookup(table, {:held, pid})
    release_slot(table, pid, signal, pool, tenant)
  end

  defp release_slot(table, pid, signal, pool, tenant) do
    case :ets.take(table, {:limited, pid}) do
      [{_, limited}] -> release_limit(table, {:limit, limited})
      [] -> :ok
    end

    :ets.update_counter(table, pool_key(pool, signal), {2, -1})
    :ets.update_counter(table, {:in_flight, signal}, {2, -1})
    # Rows with held slots are never pruned; the default only guards races.
    now = System.monotonic_time(:millisecond)
    :ets.update_counter(table, tenant, {2, -1}, {tenant, 1, now})
  end

  defp pool_key(:reserved, signal), do: {:reserved, signal}
  defp pool_key(:shared, _signal), do: :shared

  @doc "Requests currently holding a slot on this node, in total or for one signal."
  def in_flight, do: Enum.sum(Enum.map(@signals, &in_flight/1))

  def in_flight(signal) when signal in @signals, do: counter({:in_flight, signal})

  @doc "Estimated record bytes of requests waiting for publication without a slot."
  def pending_bytes, do: counter(:pending_bytes)

  defp counter(key), do: counter(table(), key)

  defp counter(table, key) do
    case :ets.lookup(table, key) do
      [{_, value}] -> value
      [{_, value, _}] -> value
      [] -> 0
    end
  rescue
    ArgumentError -> 0
  end

  @doc "Node-local admission counters and gauges for the metrics endpoint."
  def stats do
    for signal <- @signals, into: %{} do
      {signal,
       %{
         in_flight: in_flight(signal),
         admitted: counter({:outcome, signal, :admitted}),
         rejected: counter({:outcome, signal, :rejected}),
         tenant_limited: counter({:outcome, signal, :tenant_limited}),
         active_tenants: active_gauge(signal),
         handed_off: counter({:outcome, signal, :handed_off})
       }}
    end
  end

  defp active_gauge(signal) do
    case :ets.lookup(table(), {:active, signal}) do
      [{_, active, _at}] -> active
      [] -> 0
    end
  rescue
    ArgumentError -> 0
  end

  defp count(table, signal, outcome) do
    key = {:outcome, signal, outcome}
    :ets.update_counter(table, key, {2, 1}, {key, 0})
  end

  @doc false
  def limits do
    config = Pulse.Runtime.get_env(:pulse, __MODULE__, [])
    max = Keyword.get(config, :max_concurrent, @default_max)
    # Reserves never exceed the bound: every class keeps at least its reserve.
    reserved = config |> Keyword.get(:reserved_per_signal, max(1, div(max, 8))) |> min(div(max, length(@signals)))
    %{max: max, reserved: reserved, shared: max - reserved * length(@signals)}
  end

  defp max_pending_bytes do
    Keyword.get(Pulse.Runtime.get_env(:pulse, __MODULE__, []), :max_pending_bytes, @default_max_pending_bytes)
  end

  @impl true
  def init(_opts) do
    :ets.new(table(), [:named_table, :public, :set, write_concurrency: true])
    # Per-tenant ingest rate buckets (Pulse.TenantLimits), one row per tenant.
    :ets.new(Pulse.Runtime.table(Pulse.TenantLimits.table()), [:named_table, :public, :set, write_concurrency: true])
    {:ok, MapSet.new()}
  end

  @impl true
  def handle_cast({:monitor, pid}, monitored) do
    if MapSet.member?(monitored, pid) do
      {:noreply, monitored}
    else
      Process.monitor(pid)
      {:noreply, MapSet.put(monitored, pid)}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, monitored) do
    release(pid)
    {:noreply, MapSet.delete(monitored, pid)}
  end
end
