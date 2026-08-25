defmodule Tuist.Kura.Demand do
  @moduledoc """
  Records and reads Kura cache demand for an account-region instance.

  Demand is recorded at the request boundary: cache-endpoint resolution, where
  a client asks where to send cache traffic. That covers the Xcode, Module, and
  Gradle lanes uniformly, is the same call for a developer machine and for a
  runner build, and is the only signal available when an account has no
  instance at all — which is what lets an archived account ask for one back
  rather than deadlocking. General project activity, command events unrelated
  to cache, billing events, and dashboard visits never reach here.

  This clock triggers provisioning, and only provisioning. It is a proxy for
  cache traffic rather than a measure of it, and it errs in both directions.
  `tuist setup cache` installs a LaunchAgent with `RunAtLoad`, so the cache
  daemon resolves an endpoint on every login: an account whose agent is
  installed but idle keeps refreshing its clock without anyone building, and
  would never reach a full inactive window. In the other direction the CLI
  caches a resolved endpoint for an hour, so most requests during a build never
  reach here at all.

  Both errors are safe on the provisioning side, where an unnecessary instance
  is a wasted quota and a missing one is an account with no cache. They are not
  safe on the archival side, which reads bytes actually moved instead
  (`Tuist.Kura.Transfers`).

  There is a second way in, for the one case where the boundary's bias is not
  safe. `record_run/2` is a completed run that had something to cache. It
  arrives from ingest after the fact rather than from a client asking anything,
  so it separates "someone ran a build" from "a daemon woke up on login" — the
  conflation that makes the boundary over-count in the first place. It is
  coarser and later than the boundary and does not replace it; what it is for
  is releasing an account-region that the archival loop has held out of
  provisioning for going unused, which resolution alone cannot do because
  suppressing resolution is what the hold does.

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
  alias Tuist.Repo

  @table __MODULE__
  @flush_interval to_timeout(minute: 1)

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
  """
  def record(account_id) when is_integer(account_id) do
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

  def record(_account_id), do: :ok

  @doc """
  Records that the account completed a run with something in it worth caching,
  and releases any hold keeping its account-regions out of provisioning.

  Called from run ingest rather than from the request boundary, which is the
  point: a held account-region is one whose lookups the lifecycle has decided
  not to believe, so the only way for it to say it wants a cache again is a
  signal that does not depend on being served. A run is that signal — it is
  reported after the fact, and reported whether or not a cache answered.

  The cacheable count is the predicate, not the run itself. A run with nothing
  to cache would not have used an instance, so provisioning one on the strength
  of it would put the account-region straight back into probation, which is the
  cycle the hold exists to break.

  Only held rows are touched, so this is a single indexed statement that
  normally matches nothing. The demand clock is carried forward with the
  release because a run is stronger evidence of wanting a cache than the
  lookups it supersedes, and a released row with a stale clock would be
  unblocked without being provisioned.
  """
  def record_run(account_id, cacheable_count)
      when is_integer(account_id) and is_integer(cacheable_count) and cacheable_count > 0 do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    {count, _} =
      Repo.update_all(
        from(l in AccountRegionLifecycle,
          where: l.account_id == ^account_id,
          where: not is_nil(l.unused_archived_at),
          update: [
            set: [
              unused_archived_at: nil,
              last_cache_demand_at: fragment("GREATEST(?, ?)", l.last_cache_demand_at, ^now),
              updated_at: ^now
            ]
          ]
        ),
        []
      )

    count
  end

  def record_run(_account_id, _cacheable_count), do: 0

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
    if Environment.kura_demand_write_through_repo?(), do: {:ok, 0}, else: drain()
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
  Tuist-hosted default lane rather than to its own legacy custom endpoints,
  because routing archived accounts at the custom-endpoint path would make
  archival the thing that keeps that path alive.
  """
  def lifecycle_managed?(%Account{id: account_id}) do
    Repo.exists?(from(l in AccountRegionLifecycle, where: l.account_id == ^account_id))
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
  `true` for as long as that lasts, and re-resolves every 30 seconds. That is
  accepted: a region with no room is an operational problem to be alerted on
  and fixed by adding a machine, not a steady state to design around. The
  `capacity_refused` counter is the signal for it.
  """
  def instance_expected?(%Account{} = account) do
    match?({:ok, _resolution}, AccountPolicies.resolve(account))
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

  A row created here also starts its transfer clock
  (`Tuist.Kura.Transfers`), so an account-region that appears after the seeding
  backfill has run is still tracked, and still inert for the grace period.
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
    interval = Keyword.get(opts, :flush_interval, @flush_interval)
    schedule_flush(interval)
    {:ok, %{flush_interval: interval}}
  end

  @impl GenServer
  def handle_info(:flush, state) do
    drain()
    schedule_flush(state.flush_interval)
    {:noreply, state}
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

    resolutions = AccountPolicies.resolve_all(accounts)

    Enum.flat_map(accounts, fn account ->
      case Map.fetch!(resolutions, account.id) do
        {:ok, %{service_region: service_region}} ->
          [
            %{
              account_id: account.id,
              service_region: service_region,
              last_cache_demand_at: Map.fetch!(demand_at_by_account, account.id)
            }
          ]

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

    rows =
      Enum.map(rows, fn row ->
        row
        |> Map.put(:id, UUIDv7.generate())
        |> Map.update!(:last_cache_demand_at, &DateTime.truncate(&1, :second))
        |> Map.put(:transfer_tracking_started_at, now)
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
                # Coalesced, not overwritten: the archival sweep reads the
                # transfer clock and refuses to act until it has been in place
                # for the tracking grace period, so restarting it on every
                # resolution would hold every instance warm forever.
                transfer_tracking_started_at:
                  fragment(
                    "COALESCE(?, EXCLUDED.transfer_tracking_started_at)",
                    l.transfer_tracking_started_at
                  ),
                updated_at: fragment("EXCLUDED.updated_at")
              ]
            ]
          )
      )

    {:ok, count}
  end
end
