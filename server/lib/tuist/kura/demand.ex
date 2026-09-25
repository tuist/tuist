defmodule Tuist.Kura.Demand do
  @moduledoc """
  Records and reads Kura cache demand for an account-region instance.

  The shared activation gateway records authenticated cache requests and triggers
  immediate provisioning when an account has no serving instance. Fresh public
  usage reports from trusted managed nodes refresh activity while it is serving.
  Both signals work without the CLI discovering endpoints or reserving a dormant
  cache pod. General dashboard and unrelated command activity never reach here.

  Legacy endpoint resolution and runner dispatch still record demand for older
  clients. Those compatibility signals can keep an idle account warm, while new
  CLI URL derivation alone has no lifecycle side effects. Usage reports describe
  real transfers; probes and miss-only traffic do not indefinitely reserve an
  otherwise unused cache instance.

  That boundary is a hot path, so `record/1` never touches the database. It
  writes the account id into an ETS buffer; a periodic flush resolves each
  distinct account's effective plan and service region once and upserts the
  demand timestamps in a single statement. Demand is buffered by account, not
  by account-region, so the hot path never has to resolve a region: one Kura
  instance serves the account in its service region, and the flush is where
  that region is looked up.

  Losing a flush window to a crash costs at most that window's worth of
  recency on a clock measured in days, so the buffer is deliberately not
  durable. Each node buffers and flushes independently for the same reason:
  a shared buffer would need coordination to protect a clock that does not
  need protecting, and concurrent flushes cannot lose to each other because
  the upsert keeps the greater of the two timestamps.
  """
  use GenServer

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.Kura.AccountPolicies
  alias Tuist.Kura.AccountRegionLifecycle
  alias Tuist.Kura.Origins
  alias Tuist.Repo

  @table __MODULE__
  @kick_table __MODULE__.Kicks
  @flush_interval to_timeout(minute: 1)

  # How often one account may be kicked from this node. Matches both the
  # cache-endpoint answer's max-age while provisioning and
  # `Tuist.Kura.Workers.ProvisionOnDemandWorker`'s unique window, so a fleet of
  # clients asking together collapses to the same one job that window already
  # allows rather than to one write-through and one unique insert each.
  @kick_interval_ms to_timeout(second: 5)

  # Once an account has been kicked continuously for longer than a provisioning
  # attempt is given before it counts as stalled
  # (`Tuist.Kura.provisioning_stall_seconds/0`), nothing this path does is
  # going to place it: it is being refused for capacity, or its provision is
  # wedged. Both are operational problems the reconciler tick and the stalled
  # instance alert own, so the kick drops back to the tick's own cadence rather
  # than keeping a per-request cost on an account that will not be served.
  @kick_backoff_after_ms to_timeout(minute: 15)
  @kick_backoff_interval_ms to_timeout(minute: 1)

  # A gap this much past an account's allowance is a new arrival rather than a
  # continuing streak, so its backoff starts over.
  @kick_streak_reset_ms to_timeout(minute: 5)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Buffers cache demand for an account. Safe to call from any request; it is a
  single ETS write and never fails, including before the buffer has started.

  Configured to write through the repo instead of buffering, the write lands
  in the caller's connection. Tests run that way (`config/test.exs`, matching
  `Tuist.Ingestion.Bufferable`) so a process-wide buffer cannot carry one
  test's demand into another's transaction.

  `origin` is where the request came from, and is counted separately by
  `Tuist.Kura.Origins`: this clock says the account wants cache, those counts
  say where from. A `nil` origin still records demand — an account the edge
  could not locate keeps its instance warm exactly as before, it just does not
  vote on where the instance goes.

  `persist_origin: true` writes the origin count through instead of buffering
  it, for a request about to have its instance placed by a job that may run on
  another node (`Tuist.Kura.Workers.ProvisionOnDemandWorker`), where this
  node's buffer is not visible.
  """
  def record(account_id, origin \\ nil, opts \\ [])

  def record(account_id, origin, opts) when is_integer(account_id) do
    Origins.record_demand(account_id, origin, persist: Keyword.get(opts, :persist_origin, false))

    if Environment.kura_demand_write_through_repo?() do
      persist([{account_id, System.system_time(:second)}])
      :ok
    else
      :ets.insert(@table, {account_id, System.system_time(:second)})
      :ok
    end
  rescue
    ArgumentError -> :ok
  end

  def record(_account_id, _origin, _opts), do: :ok

  @doc """
  Drains this node's buffer into `kura_account_region_lifecycles`. Called on
  the flush timer, and directly by the archival sweep so demand recorded
  moments earlier on the sweeping node is not read as absence.

  Every node runs its own buffer and its own flush timer, so a sweep drains
  only what its own node holds; the other nodes carry up to a flush interval
  of demand the sweep cannot see. That is a minute against a window measured
  in days, and it self-corrects rather than costing an instance: the demand
  lands on the next flush, and drain resolution cancels an archival the
  moment it does, well inside the drain window. Making the sweep drain the
  cluster would trade real coordination for a minute of recency on a 90-day
  clock.

  The drain runs in the calling process rather than in the buffer: the table
  is public and `:ets.take/2` is atomic, so concurrent flushes are safe, and
  the writes stay in the caller's transaction and connection.
  """
  def flush do
    # Origins first, and in the same connection: resolution reads the day's
    # counts, so an account whose very first request this is gets placed from
    # its own origin rather than from the default it would resolve to a moment
    # before the counts landed.
    Origins.flush()

    if Environment.kura_demand_write_through_repo?(), do: {:ok, 0}, else: drain()
  end

  @doc """
  Whether this node should act on an account's unserved cache-endpoint
  resolution now, rather than leave it to the one it already acted on.

  Acting costs a write-through of the request's origin and a unique job insert,
  which for an account with no instance serving is every client of that account
  on every request. That is the right price once, for the account about to be
  provisioned; paying it per request buys nothing, because the work it
  schedules is deduplicated anyway.

  Returns `true` for the first resolution in `@kick_interval_ms`, and backs a
  long streak off to the reconciler's own cadence — see `@kick_backoff_after_ms`.
  Returns `true` unconditionally before the buffer has started, so a node
  without it behaves as it did.
  """
  def claim_provision_kick(account_id) when is_integer(account_id) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@kick_table, account_id) do
      [{^account_id, next_allowed_ms, _streak_started_ms}] when next_allowed_ms > now ->
        false

      [{^account_id, next_allowed_ms, streak_started_ms}] ->
        streak_started_ms =
          if now - next_allowed_ms > @kick_streak_reset_ms, do: now, else: streak_started_ms

        claim(account_id, now, streak_started_ms)

      [] ->
        claim(account_id, now, now)
    end
  rescue
    # Racing a node that has not started its buffer yet: kick rather than
    # silently turning the fast path off.
    ArgumentError -> true
  end

  def claim_provision_kick(_account_id), do: false

  defp claim(account_id, now, streak_started_ms) do
    interval =
      if now - streak_started_ms > @kick_backoff_after_ms,
        do: @kick_backoff_interval_ms,
        else: @kick_interval_ms

    :ets.insert(@kick_table, {account_id, now + interval, streak_started_ms})
    true
  end

  @doc """
  Writes one account's demand through the caller's connection at once, instead
  of leaving it in this node's buffer. For a caller that is about to act on the
  demand, possibly on another node, and so cannot wait for a flush.
  """
  def persist_now(account_id, %DateTime{} = demand_at) do
    persist([{account_id, DateTime.to_unix(demand_at)}])
  end

  @doc """
  The lifecycle row for an account-region, or `nil` when the account has never
  asked for Kura cache in that region.
  """
  def get(account_id, service_region) do
    Repo.get_by(AccountRegionLifecycle, account_id: account_id, service_region: service_region)
  end

  @doc """
  True when the account is under the demand-driven lifecycle in any region.

  Cache-endpoint resolution uses this to decide what to answer while no Kura
  instance is serving: a lifecycle-managed account falls back to the
  Tuist-hosted default lane, or gets no endpoints for a client that is always
  routed to Kura, rather than to its own legacy custom endpoints, because
  routing archived accounts at the custom-endpoint path would make archival the
  thing that keeps that path alive.
  """
  def lifecycle_managed?(%Account{id: account_id}) do
    Repo.exists?(from(l in AccountRegionLifecycle, where: l.account_id == ^account_id))
  end

  @doc """
  True when an instance of the account was reclaimed for never storing anything
  and has not been returned since. Only cache demand recorded after that
  archival returns it.
  """
  def unused_hold?(%Account{id: account_id}) do
    Repo.exists?(from(l in AccountRegionLifecycle, where: l.account_id == ^account_id and l.drain_reason == :unused))
  end

  @doc """
  Whether a Kura instance is expected to start serving for this account
  shortly, so a client should treat an endpoint answer as short-lived.

  True whenever the account resolves to a service region, which is checked
  only where no Kura endpoint is being served. That is deliberately broader
  than "an instance row already exists": the request asking this question is
  itself the one that records the demand a cold return is provisioned from, so
  on the first request after an archive there is no row yet and a narrower
  check would report `false` on the one request where the answer matters most,
  leaving the client caching a stand-in lane for its full interval.

  The cost is that an account the region keeps refusing for capacity reports
  `true` for as long as that lasts, and re-resolves on the provisioning
  answer's short max age. That is accepted: a region with no room is an
  operational problem to be alerted on and fixed by adding a machine, not a
  steady state to design around, and `claim_provision_kick/1` keeps the
  re-resolutions from each doing provisioning work. The `capacity_refused`
  counter is the signal for it.

  Resolved without reading room and without recording a placement
  (`AccountPolicies.resolvable?/1`): the answer does not depend on which
  region, and a request is not where a placement should be taken.
  """
  def instance_expected?(%Account{} = account) do
    AccountPolicies.resolvable?(account)
  end

  @doc """
  Upserts demand for one account-region, keeping the latest timestamp. Used by
  the backfill, which resolves regions from historical analytics rather than
  from the buffer.
  """
  def upsert(account_id, service_region, %DateTime{} = demand_at) do
    upsert_many([%{account_id: account_id, service_region: service_region, last_cache_demand_at: demand_at}])
  end

  @doc """
  Upserts a batch of account-region demand rows in one statement, keeping the
  latest timestamp per row. The backfill seeds thousands of rows at once, so it
  goes through here rather than paying a round trip each.

  Rows are `%{account_id:, service_region:, last_cache_demand_at:}`.
  """
  def upsert_many(rows) when is_list(rows), do: upsert_all(rows)

  @doc """
  Sets or clears the keep-warm exception for an account-region. A keep-warm
  instance is never drained and never counted as archival-eligible; it holds
  its full allocation while inactive.
  """
  def set_keep_warm(account_id, service_region, keep_warm?) when is_boolean(keep_warm?) do
    case get(account_id, service_region) do
      nil ->
        {:error, :not_found}

      %AccountRegionLifecycle{} = lifecycle ->
        lifecycle
        |> AccountRegionLifecycle.keep_warm_changeset(%{keep_warm: keep_warm?})
        |> Repo.update()
    end
  end

  @impl GenServer
  def init(opts) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    :ets.new(@kick_table, [:named_table, :public, :set, write_concurrency: true, read_concurrency: true])
    interval = Keyword.get(opts, :flush_interval, @flush_interval)
    schedule_flush(interval)
    {:ok, %{flush_interval: interval}}
  end

  @impl GenServer
  def handle_info(:flush, state) do
    drain()
    expire_kicks()
    schedule_flush(state.flush_interval)
    {:noreply, state}
  end

  # An account that stopped asking keeps no row: its next resolution starts a
  # fresh streak anyway, so the entry only holds memory.
  defp expire_kicks do
    cutoff = System.monotonic_time(:millisecond) - @kick_streak_reset_ms

    :ets.select_delete(@kick_table, [
      {{:_, :"$1", :_}, [{:<, :"$1", cutoff}], [true]}
    ])
  end

  defp schedule_flush(interval), do: Process.send_after(self(), :flush, interval)

  # `:ets.take/2` reads and removes each key atomically, so a `record/1`
  # racing the drain either lands before the take (and is persisted) or after
  # it (and survives for the next flush). Nothing is dropped in between.
  defp drain do
    @table
    |> :ets.select([{{:"$1", :_}, [], [:"$1"]}])
    |> Enum.flat_map(&:ets.take(@table, &1))
    |> persist()
  end

  defp persist(entries) do
    entries
    |> rows_for()
    |> upsert_all()
  end

  defp rows_for([]), do: []

  defp rows_for(entries) do
    demand_at_by_account =
      Map.new(entries, fn {account_id, recorded_at} ->
        {account_id, DateTime.from_unix!(recorded_at)}
      end)

    accounts =
      demand_at_by_account
      |> Map.keys()
      |> accounts_with_subscriptions()

    resolutions = AccountPolicies.serving_regions_all(accounts)

    Enum.flat_map(accounts, fn account ->
      case Map.fetch!(resolutions, account.id) do
        # One row per region the account is served from. An account placement
        # has expanded is warm in every one of them off the same demand, which
        # is what makes a secondary hold its place: the inactivity rules read
        # the account's clock, and whether a secondary is still worth its slot
        # is a placement decision measured on its region's own traffic, not
        # something to infer from a clock every region shares.
        {:ok, service_regions} ->
          Enum.map(service_regions, fn service_region ->
            %{
              account_id: account.id,
              service_region: service_region,
              last_cache_demand_at: Map.fetch!(demand_at_by_account, account.id)
            }
          end)

        # An account whose plan or region cannot be resolved has no
        # account-region instance to keep warm, so there is nothing to record.
        # It keeps being served by whatever lane it is on today.
        {:error, _reason} ->
          []
      end
    end)
  end

  defp accounts_with_subscriptions(account_ids) do
    Repo.all(
      from(a in Account,
        where: a.id in ^account_ids,
        preload: [:subscriptions]
      )
    )
  end

  defp upsert_all([]), do: {:ok, 0}

  defp upsert_all(rows) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.transaction(fn ->
      live_account_ids = lock_live_account_ids(Enum.map(rows, & &1.account_id))

      rows =
        rows
        |> Enum.filter(&MapSet.member?(live_account_ids, &1.account_id))
        |> Enum.map(fn row ->
          row
          |> Map.put(:id, UUIDv7.generate())
          |> Map.update!(:last_cache_demand_at, &DateTime.truncate(&1, :second))
          |> Map.put(:inserted_at, now)
          |> Map.put(:updated_at, now)
        end)

      {count, _} =
        Repo.insert_all(AccountRegionLifecycle, rows,
          conflict_target: [:account_id, :service_region],
          on_conflict:
            from(l in AccountRegionLifecycle,
              update: [
                set: [
                  last_cache_demand_at: fragment("GREATEST(?, EXCLUDED.last_cache_demand_at)", l.last_cache_demand_at),
                  updated_at: fragment("EXCLUDED.updated_at")
                ]
              ]
            )
        )

      count
    end)
  end

  # An account deleted between resolving its region and this insert would fail
  # the foreign key and crash the buffer, dropping every other account's
  # buffered demand with it. The key-share lock holds off a concurrent delete
  # until the insert commits; an already-deleted account is simply skipped.
  defp lock_live_account_ids(account_ids) do
    from(a in Account,
      where: a.id in ^Enum.uniq(account_ids),
      order_by: a.id,
      select: a.id,
      lock: "FOR KEY SHARE"
    )
    |> Repo.all()
    |> MapSet.new()
  end
end
